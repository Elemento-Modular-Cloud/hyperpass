/*
 * Copyright (C) Elemento.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "llm_service.h"

#include "backend_probe.h"
#include "binary_locator.h"
#include "gguf_file_pick.h"
#include "managed_tools.h"
#include "mlx_repo.h"
#include "openai_compat_client.h"
#include "runtime_installer.h"
#include "runners/model_format.h"

#include <multipass/constants.h>
#include <multipass/file_ops.h>
#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/memory_size.h>
#include <multipass/platform.h>
#include <multipass/process/simple_process_spec.h>
#include <multipass/process/process_scan.h>
#include <multipass/settings/settings.h>
#include <multipass/utils.h>

#include <QEventLoop>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTcpServer>
#include <QThread>
#include <QTimer>
#include <QUrl>
#include <QUuid>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <future>
#include <memory>
#include <stdexcept>
#include <unordered_set>

namespace mp = multipass;
namespace mpl = multipass::logging;
namespace mpu = mp::utils;

namespace
{
constexpr auto category = "llm";

bool is_inference_runner_id(const std::string& id)
{
    return id == mp::llm::runner_llamacpp || id == mp::llm::runner_vllm ||
           (mp::enable_mlx_backend && id == mp::llm::runner_mlx);
}

std::unordered_set<std::string> ready_inference_runtimes(const QString& managed_tools_dir)
{
    std::unordered_set<std::string> ready;
    for (const auto& row : mp::llm::probe_backends({}, managed_tools_dir))
    {
        if (row.status == "ready" && is_inference_runner_id(row.id))
            ready.insert(row.id);
    }
    return ready;
}

std::vector<std::string> ordered_ready_runtimes(const std::unordered_set<std::string>& ready)
{
    std::vector<std::string> ordered;
    for (const auto* id :
         {mp::llm::runner_llamacpp, mp::llm::runner_vllm, mp::llm::runner_mlx})
    {
        if (ready.contains(id))
            ordered.emplace_back(id);
    }
    return ordered;
}

bool model_supported_by_ready(const mp::ModelSuggestion& model,
                              const std::unordered_set<std::string>& ready)
{
    if (ready.empty())
        return false;
    if (model.supported_runtimes_size() == 0)
        return true;
    for (const auto& runtime : model.supported_runtimes())
    {
        if (ready.contains(runtime))
            return true;
    }
    return false;
}

void stamp_catalog_model_runtimes(mp::ModelSuggestion& model)
{
    if (model.format().empty())
    {
        const auto rt = QString::fromStdString(model.runtime()).toLower();
        if (rt.contains("mlx"))
            model.set_format(mp::llm::format_mlx);
        else if (rt.contains("vllm") || rt.contains("hf") || rt.contains("transformers"))
            model.set_format(mp::llm::format_hf);
        else
            model.set_format(mp::llm::format_gguf);
    }
    if (model.supported_runtimes_size() == 0)
    {
        const auto fmt = model.format();
        if (fmt == mp::llm::format_mlx)
            model.add_supported_runtimes(mp::llm::runner_mlx);
        else if (fmt == mp::llm::format_hf)
            model.add_supported_runtimes(mp::llm::runner_vllm);
        else
            model.add_supported_runtimes(mp::llm::runner_llamacpp);
    }
}

void append_unique_models(std::vector<mp::ModelSuggestion>& into,
                          std::vector<mp::ModelSuggestion> batch,
                          std::unordered_set<std::string>& seen_ids)
{
    for (auto& model : batch)
    {
        const auto id = model.id();
        if (id.empty() || !seen_ids.insert(id).second)
            continue;
        into.push_back(std::move(model));
    }
}

std::string slug(const std::string& model_id)
{
    std::string out;
    out.reserve(model_id.size());
    for (char c : model_id)
    {
        if (std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_')
            out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
        else
            out.push_back('-');
    }
    return out;
}

bool session_matches_model(const mp::LoadedSession& session, const std::string& model_id)
{
    return session.model_id == model_id || session.openai_id == model_id ||
           session.upstream_model_id == model_id || session.instance_id == model_id;
}

constexpr auto cloud_unload_error =
    "cloud models cannot be unloaded while the provider is configured";

} // namespace

mp::LlmService::LlmService(ResourcePool& pool, URLDownloader& downloader, Path data_directory)
    : pool{pool},
      vault{data_directory, downloader},
      advisor{llm::managed_tools_root(data_directory)},
      keys{data_directory},
      providers{data_directory},
      downloader{downloader},
      data_directory{data_directory}
{
    activity_log.set_log_directory(QDir{data_directory}.filePath("llm/logs"));
    idle_timer.setInterval(15000);
    QObject::connect(&idle_timer, &QTimer::timeout, this, [this] { idle_unload_tick(); });
    idle_timer.start();
    restore_claims();
    QTimer::singleShot(0, this, [this] { restore_provider_models(); });
}

mp::LlmService::~LlmService()
{
    idle_timer.stop();
    std::vector<std::pair<std::string, std::unique_ptr<Process>>> dying;
    {
        std::lock_guard lock{mutex};
        for (auto& [name, session] : sessions)
        {
            if (session.process)
                dying.emplace_back(name, std::move(session.process));
            if (session.runner_thread)
            {
                session.runner_thread->quit();
                session.runner_thread->wait(5000);
            }
            pool.release(name);
        }
        sessions.clear();
    }
    for (auto& [_, process] : dying)
        stop_process(process.get());
}

void mp::LlmService::restore_claims()
{
    std::vector<LoadedSession> recovered;
    std::unordered_map<qint64, QString> live_cmds;
    for (const auto& proc : mpu::list_processes())
    {
        if (proc.command_line.contains("llama-server") || proc.command_line.contains("llama_server") ||
            proc.command_line.contains("mlx_lm.server") || proc.command_line.contains("vllm"))
        {
            live_cmds[proc.pid] = proc.command_line;
        }
    }

    QFile file{sessions_file()};
    QJsonArray persisted;
    if (MP_FILEOPS.open(file, QIODevice::ReadOnly))
    {
        const auto doc = QJsonDocument::fromJson(MP_FILEOPS.read_all(file));
        if (doc.isObject())
            persisted = doc.object().value("sessions").toArray();
        file.close();
    }

    std::unordered_set<qint64> claimed_pids;
    for (const auto& value : persisted)
    {
        const auto obj = value.toObject();
        LoadedSession session;
        session.instance_id = obj.value("instance_id").toString().toStdString();
        session.model_id = obj.value("model_id").toString().toStdString();
        session.openai_id = obj.value("openai_id").toString().toStdString();
        session.backend = obj.value("backend").toString().toStdString();
        session.path = obj.value("path").toString().toStdString();
        session.port = obj.value("port").toInt();
        session.pid = obj.value("pid").toInteger();
        session.memory = MemorySize::from_bytes(obj.value("memory_bytes").toInteger());
        session.max_tokens = obj.value("max_tokens").toInt();
        session.ctx_size = obj.value("ctx_size").toInt(4096);
        if (session.ctx_size <= 0)
            session.ctx_size = 4096;
        if (obj.value("params").isObject())
            session.params = llm_load_params_from_json(obj.value("params").toObject());
        session.intent = obj.value("intent").toString().toStdString();
        session.intent_role = obj.value("intent_role").toString().toStdString();
        session.provider_id = obj.value("provider_id").toString().toStdString();
        session.upstream_model_id = obj.value("upstream_model_id").toString().toStdString();
        session.owned_by = obj.value("owned_by").toString().toStdString();
        if (session.instance_id.empty())
            continue;
        if (session_is_remote(session))
        {
            if (!providers.get(session.provider_id))
                continue;
            if (session.upstream_model_id.empty())
                session.upstream_model_id = session.openai_id;
            if (session.backend.empty())
                session.backend = openai_compat_backend;
            recovered.push_back(std::move(session));
            continue;
        }
        if (!session_is_live(session) && live_cmds.find(session.pid) == live_cmds.end())
            continue;
        // Pid can stay alive while the HTTP server is wedged (mlx_lm accepts then EOFs).
        if (session.port > 0 && !backend_http_reachable(session.port))
        {
            mpl::warn(category,
                      "Dropping restored LLM instance '{}' — pid {} port {} not serving HTTP",
                      session.instance_id,
                      session.pid,
                      session.port);
            if (session.pid > 0)
                mpu::terminate_pid(session.pid);
            continue;
        }
        if (session.pid > 0)
            claimed_pids.insert(session.pid);
        recovered.push_back(std::move(session));
    }

    for (const auto& [pid, cmdline] : live_cmds)
    {
        if (claimed_pids.contains(pid))
            continue;
        LoadedSession session;
        session.pid = pid;
        session.port = mpu::cli_flag_value(cmdline, {"--port"}).toInt();
        session.path = mpu::cli_flag_value(cmdline, {"-m", "--model"}).toStdString();
        session.openai_id = mpu::cli_flag_value(cmdline, {"--alias"}).toStdString();
        session.ctx_size = mpu::cli_flag_value(cmdline, {"--ctx-size", "-c"}).toInt();
        if (session.ctx_size <= 0)
            session.ctx_size = 4096;
        session.max_tokens = mpu::cli_flag_value(cmdline, {"--n-predict"}).toInt();
        if (session.max_tokens < 0)
            session.max_tokens = 0;
        session.backend = cmdline.contains("mlx_lm") ? "mlx" : "llamacpp";
        if (session.openai_id.empty())
            session.openai_id = fmt::format("recovered-{}", pid);
        session.instance_id = session.openai_id;
        session.model_id = session.path.empty()
                               ? session.openai_id
                               : QFileInfo{QString::fromStdString(session.path)}.completeBaseName().toStdString();
        for (const auto& art : vault.list())
        {
            if (art.path == session.path)
            {
                session.model_id = art.id;
                session.memory = MemorySize::from_bytes(art.size_bytes);
                break;
            }
        }
        if (session.port > 0 && !backend_http_reachable(session.port))
        {
            mpl::warn(category,
                      "Ignoring orphan inference pid {} — port {} not serving HTTP",
                      pid,
                      session.port);
            mpu::terminate_pid(pid);
            continue;
        }
        recovered.push_back(std::move(session));
    }

    for (auto& session : recovered)
        restore_session(std::move(session));
    persist_sessions();
}

void mp::LlmService::restore_provider_models()
{
    for (const auto& rec : providers.list())
    {
        try
        {
            const auto result = refresh_provider_models(rec);
            mpl::info(category,
                      "Restored cloud provider '{}' (+{} kept {} removed {})",
                      rec.label.empty() ? rec.id : rec.label,
                      result.added,
                      result.kept,
                      result.removed);
        }
        catch (const std::exception& e)
        {
            mpl::warn(category,
                      "failed to restore cloud provider '{}': {}",
                      rec.label.empty() ? rec.id : rec.label,
                      e.what());
        }
    }
}

mp::MemorySize mp::LlmService::estimate_claim(const ModelArtifact& artifact,
                                              int ctx_size,
                                              const std::string& cache_type_k,
                                              const std::string& cache_type_v) const
{
    const auto file_bytes = std::max(0LL, artifact.size_bytes);
    const auto scale = kv_cache_byte_scale(cache_type_k, cache_type_v);
    const auto kv = static_cast<long long>(
        static_cast<double>(std::max(ctx_size, 2048)) * 2.0 * 1024.0 * 1024.0 / 8.0 * scale);
    const auto overhead = 512LL * 1024 * 1024;
    return MemorySize::from_bytes(file_bytes + kv + overhead);
}

int mp::LlmService::pick_loopback_port() const
{
    QTcpServer server;
    if (!server.listen(QHostAddress::LocalHost, 0))
        throw std::runtime_error("unable to allocate a loopback port for llama-server");
    const auto port = server.serverPort();
    server.close();
    return port;
}

bool mp::LlmService::backend_http_reachable(int port, int timeout_ms) const
{
    if (port <= 0)
        return false;
    QNetworkAccessManager manager;
    const QUrl models_url{QStringLiteral("http://127.0.0.1:%1/v1/models").arg(port)};
    QEventLoop loop;
    QTimer timeout;
    timeout.setSingleShot(true);
    timeout.setInterval(std::max(250, timeout_ms));
    auto* reply = manager.get(QNetworkRequest{models_url});
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
    timeout.start();
    loop.exec();
    const bool ok = reply->error() == QNetworkReply::NoError &&
                    reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() > 0;
    reply->deleteLater();
    return ok;
}

std::string mp::LlmService::recent_backend_log_snippet(const std::string& instance_id,
                                                       std::size_t max_lines) const
{
    if (instance_id.empty() || max_lines == 0)
        return {};
    const auto entries = activity_log.snapshot(instance_id);

    auto is_noise = [](const QString& msg) {
        if (msg.contains(QLatin1String("otel.py")) && msg.contains(QLatin1String("sync_wrapper")))
            return true;
        if (msg.contains(QRegularExpression{QStringLiteral(R"(^\^+$)")}))
            return true;
        if (msg.startsWith(QLatin1String("return func(")) ||
            msg.startsWith(QLatin1String("return AsyncMPClient")) ||
            msg.startsWith(QLatin1String("return SyncMPClient")))
            return true;
        return false;
    };
    auto score = [](const QString& msg) {
        const auto lower = msg.toLower();
        int s = 1;
        if (lower.contains(QLatin1String("valueerror")) ||
            lower.contains(QLatin1String("runtimeerror")) ||
            lower.contains(QLatin1String("oserror")) ||
            lower.contains(QLatin1String("cuda")) ||
            lower.contains(QLatin1String("out of memory")) ||
            lower.contains(QLatin1String("oom")))
            s += 8;
        if (lower.contains(QLatin1String("engine core")) ||
            lower.contains(QLatin1String("kv cache")) ||
            lower.contains(QLatin1String("max_model_len")) ||
            lower.contains(QLatin1String("gpu_memory")) ||
            lower.contains(QLatin1String("architecture")) ||
            lower.contains(QLatin1String("does not recognize")))
            s += 10;
        if (lower.contains(QLatin1String("error")) || lower.contains(QLatin1String("exception")) ||
            lower.contains(QLatin1String("traceback")) || lower.contains(QLatin1String("failed")))
            s += 4;
        if (msg.startsWith(QLatin1String("File \"")) || msg.contains(QLatin1String("^^^^")))
            s -= 4;
        return s;
    };

    struct Scored
    {
        int score{0};
        std::size_t order{0};
        std::string text;
    };
    std::vector<Scored> scored;
    std::size_t order = 0;
    for (const auto& entry : entries)
    {
        if (entry.source() != "process" && entry.level() != "error" && entry.level() != "warning")
            continue;
        const auto msg = QString::fromStdString(entry.message()).trimmed();
        if (msg.isEmpty() || is_noise(msg))
            continue;
        scored.push_back(Scored{score(msg), order++, msg.toStdString()});
    }
    if (scored.empty())
        return {};

    std::stable_sort(scored.begin(), scored.end(), [](const Scored& a, const Scored& b) {
        if (a.score != b.score)
            return a.score > b.score;
        return a.order > b.order; // prefer later lines among equals
    });

    const auto take = std::min(max_lines, scored.size());
    std::vector<Scored> picked(scored.begin(), scored.begin() + static_cast<std::ptrdiff_t>(take));
    std::sort(picked.begin(), picked.end(), [](const Scored& a, const Scored& b) {
        return a.order < b.order;
    });

    std::vector<std::string> lines;
    lines.reserve(picked.size());
    for (const auto& row : picked)
        lines.push_back(row.text);
    return fmt::format("\n--- backend log ---\n{}", fmt::join(lines, "\n"));
}

bool mp::LlmService::wait_until_ready(int port,
                                      bool warm_load,
                                      const std::string& warm_model_id,
                                      Process* process,
                                      int http_timeout_sec) const
{
    QNetworkAccessManager manager;
    bool http_up = false;
    const auto deadline_sec = std::max(1, http_timeout_sec);
    for (int i = 0; i < deadline_sec; ++i)
    {
        if (process && !process->running())
            return false;
        if (backend_http_reachable(port, 1000))
        {
            http_up = true;
            break;
        }
        QEventLoop pause;
        QTimer::singleShot(1000, &pause, &QEventLoop::quit);
        pause.exec();
    }
    if (!http_up)
        return false;
    if (!warm_load)
        return true;

    // mlx_lm.server binds HTTP before weights finish downloading/loading. Probe with a
    // tiny completion so "load complete" means the model can actually answer.
    // IMPORTANT: the OpenAI `model` field must be the real --model id (e.g.
    // mlx-community/Gemma-2-2B-4bit). A placeholder like "warmup" makes mlx_lm try to
    // fetch that string as a Hugging Face repo and never becomes ready.
    const auto model_name =
        warm_model_id.empty() ? std::string{"default"} : warm_model_id;
    const QUrl chat_url{QStringLiteral("http://127.0.0.1:%1/v1/chat/completions").arg(port)};
    QJsonObject body;
    body.insert("model", QString::fromStdString(model_name));
    body.insert("max_tokens", 1);
    // Keep warm-up off the continuous-batching path (same Gemma2 mask bug).
    body.insert("seed", 1);
    body.insert("messages",
                QJsonArray{QJsonObject{{"role", "user"}, {"content", "ping"}}});
    const auto payload = QJsonDocument{body}.toJson(QJsonDocument::Compact);

    for (int i = 0; i < 60; ++i)
    {
        if (process && !process->running())
            return false;

        QNetworkRequest request{chat_url};
        request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
        QEventLoop loop;
        QTimer timeout;
        timeout.setSingleShot(true);
        // Weights may still be fetching from Hugging Face; allow several minutes per try.
        timeout.setInterval(180000);
        auto* reply = manager.post(request, payload);
        QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
        QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
        timeout.start();
        loop.exec();

        const auto status =
            reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto bytes = reply->readAll();
        const auto err = reply->error();
        reply->deleteLater();

        if (err == QNetworkReply::NoError && status >= 200 && status < 300)
        {
            const auto doc = QJsonDocument::fromJson(bytes);
            if (doc.isObject() && doc.object().value("choices").isArray() &&
                !doc.object().value("choices").toArray().isEmpty())
                return true;
        }

        // Connection refused / process gone — do not keep waiting.
        if (err == QNetworkReply::ConnectionRefusedError ||
            err == QNetworkReply::RemoteHostClosedError)
            return false;

        QEventLoop pause;
        QTimer::singleShot(2000, &pause, &QEventLoop::quit);
        pause.exec();
    }
    return false;
}

void mp::LlmService::ensure_backend_ready(Process* process,
                                          int port,
                                          const std::string& instance_id,
                                          const std::string& runner_id,
                                          bool warm_load,
                                          const std::string& warm_model_id)
{
    // vLLM imports CUDA + loads HF weights before binding HTTP; 30s was far too short
    // and made the process look like it "appeared then disappeared" when we killed it.
    int http_timeout_sec = 180;
    if (runner_id == llm::runner_vllm)
        http_timeout_sec = 900;
    else if (runner_id == llm::runner_mlx)
        http_timeout_sec = 600;

    log_lifecycle(instance_id,
                  "info",
                  fmt::format("waiting up to {}s for {} on 127.0.0.1:{}",
                              http_timeout_sec,
                              runner_id,
                              port));

    const bool ready =
        wait_until_ready(port, warm_load, warm_model_id, process, http_timeout_sec);
    if (ready)
        return;

    const auto snippet = recent_backend_log_snippet(instance_id);
    if (process && !process->running())
    {
        auto detail = process->process_state().failure_message().toStdString();
        if (detail.empty())
            detail = process->error_string().toStdString();
        if (detail.empty())
            detail = "process exited";
        throw std::runtime_error(fmt::format("{} exited before becoming ready: {}{}",
                                             runner_id,
                                             detail,
                                             snippet));
    }
    throw std::runtime_error(
        fmt::format("{} started but did not become ready on 127.0.0.1:{} within {}s{}",
                    runner_id,
                    port,
                    http_timeout_sec,
                    snippet));
}

std::string mp::LlmService::hf_token() const
{
    try
    {
        const auto from_settings = MP_SETTINGS.get(mp::llm_hf_token_key).toStdString();
        if (!from_settings.empty())
            return from_settings;
    }
    catch (const std::exception&)
    {
    }
    return qEnvironmentVariable(mp::hf_token_env_var).toStdString();
}

std::chrono::seconds mp::LlmService::idle_ttl() const
{
    QString val = mp::default_llm_idle_unload;
    try
    {
        val = MP_SETTINGS.get(mp::llm_idle_unload_key);
    }
    catch (const std::exception&)
    {
    }
    val = val.toLower().trimmed();
    if (val == "off" || val == "0" || val.isEmpty())
        return std::chrono::seconds{0};
    const auto unit = val.back();
    bool ok = false;
    const auto num = val.left(val.size() - 1).toInt(&ok);
    if (!ok || num <= 0)
        return std::chrono::seconds{0};
    if (unit == 'h')
        return std::chrono::hours{num};
    if (unit == 's')
        return std::chrono::seconds{num};
    return std::chrono::minutes{num};
}

std::string mp::LlmService::openai_id_for_instance(const std::string& model_id,
                                                   const std::string& instance_id) const
{
    auto base = slug(model_id);
    auto suffix = instance_id;
    std::erase(suffix, '-');
    if (suffix.size() > 8)
        suffix = suffix.substr(0, 8);
    return fmt::format("{}-{}", base, suffix);
}

mp::ResolvedGguf mp::LlmService::resolve_or_throw(const std::string& model_id,
                                                  const std::string& quant,
                                                  const std::string& hf_repo)
{
    if (auto resolved = advisor.resolve(model_id, quant, hf_repo))
        return *resolved;

    throw std::runtime_error(fmt::format(
        "could not resolve a GGUF file for '{}'. llmfit suggestions are often MLX or base "
        "checkpoints; Electros LaunchPad downloads a matching GGUF via `llmfit download --list`. "
        "Try a GGUF repo id such as bartowski/Qwen2.5-Coder-7B-Instruct-GGUF",
        model_id));
}

std::string mp::LlmService::resolve_hf_repo(const std::string& model_id,
                                            const std::string& quant,
                                            const std::string& hf_repo)
{
    if (!hf_repo.empty())
        return hf_repo;
    if (model_id.find('/') != std::string::npos)
        return model_id;
    if (auto resolved = advisor.resolve(model_id, quant, hf_repo))
    {
        if (!resolved->repo.empty())
            return resolved->repo;
    }
    throw std::runtime_error(fmt::format(
        "could not resolve a Hugging Face repo for '{}'. Pass a repo id like org/model.",
        model_id));
}

mp::ModelArtifact mp::LlmService::ensure_pulled(const std::string& model_id,
                                                const std::string& quant,
                                                const std::string& hf_repo,
                                                const ProgressMonitor& monitor,
                                                const std::string& format,
                                                const std::string& filename)
{
    const auto fmt = format.empty() ? llm::format_gguf : format;

    if (fmt == llm::format_mlx)
    {
        const auto candidates = llm::mlx_repo_candidates(model_id, quant, hf_repo);
        if (candidates.empty())
            throw std::runtime_error(fmt::format(
                "could not resolve an MLX Hugging Face repo for '{}'", model_id));

        std::string last_error;
        for (const auto& repo : candidates)
        {
            try
            {
                return vault.pull_remote(model_id, repo, fmt, quant, hf_token(), monitor);
            }
            catch (const std::exception& e)
            {
                last_error = e.what();
                mpl::warn(category,
                          "MLX snapshot '{}' unavailable ({}); trying next candidate",
                          repo,
                          e.what());
            }
        }
        throw std::runtime_error(fmt::format(
            "could not download an MLX snapshot for '{}': {}", model_id, last_error));
    }

    if (fmt == llm::format_hf)
    {
        const auto repo = resolve_hf_repo(model_id, quant, hf_repo);
        return vault.pull_remote(model_id, repo, fmt, quant, hf_token(), monitor);
    }

    if (!filename.empty())
    {
        const auto effective_quant =
            quant.empty()
                ? infer_quant_from_gguf_filename(QString::fromStdString(filename)).toStdString()
                : quant;
        if (auto existing = vault.find(model_id, llm::format_gguf, effective_quant))
        {
            const auto existing_name =
                QFileInfo{QString::fromStdString(existing->path)}.fileName();
            const bool same_file =
                QString::fromStdString(existing->filename)
                        .compare(QString::fromStdString(filename), Qt::CaseInsensitive) == 0 ||
                existing_name.compare(QString::fromStdString(filename), Qt::CaseInsensitive) == 0;
            if (same_file && !is_mmproj_gguf(existing_name) &&
                QFileInfo{QString::fromStdString(existing->path)}.exists())
            {
                if (existing->mmproj_path.empty())
                {
                    if (auto sibling = find_sibling_mmproj(QString::fromStdString(existing->path));
                        !sibling.isEmpty())
                        return vault.attach_mmproj(model_id, effective_quant, sibling.toStdString());
                }
                return *existing;
            }
        }

        const auto repo = hf_repo.empty() ? resolve_hf_repo(model_id, quant, hf_repo) : hf_repo;
        std::string mmproj;
        if (auto listed = advisor.list_gguf_files(model_id, repo))
            mmproj = listed->mmproj_filename;
        return vault.pull(model_id, repo, filename, effective_quant, hf_token(), monitor, mmproj);
    }

    if (auto existing = vault.find(model_id, llm::format_gguf, quant))
    {
        const auto path_name =
            QFileInfo{QString::fromStdString(existing->path)}.fileName();
        const bool projector = is_mmproj_gguf(QString::fromStdString(existing->filename)) ||
                               is_mmproj_gguf(path_name);
        if (!projector)
        {
            if (existing->mmproj_path.empty())
            {
                if (auto sibling = find_sibling_mmproj(QString::fromStdString(existing->path));
                    !sibling.isEmpty())
                    return vault.attach_mmproj(model_id, existing->quant, sibling.toStdString());
            }
            return *existing;
        }
    }

    const auto resolved = resolve_or_throw(model_id, quant, hf_repo);
    if (resolved.filename.empty())
        throw std::runtime_error("llmfit listed the repo but did not name a GGUF file");
    if (is_mmproj_gguf(QString::fromStdString(resolved.filename)))
        throw std::runtime_error(
            "could not find a main GGUF (only a CLIP mmproj projector was listed)");
    return vault.pull(model_id,
                      resolved.repo,
                      resolved.filename,
                      quant,
                      hf_token(),
                      monitor,
                      resolved.mmproj_filename);
}

void mp::LlmService::find_models(
    const FindModelsRequest* request,
    grpc::ServerReaderWriterInterface<FindModelsReply, FindModelsRequest>* server)
{
    FindModelsReply reply;
    try
    {
        const auto tools_root = llm::managed_tools_root(data_directory);
        const auto ready = ready_inference_runtimes(tools_root);
        auto runtime = request->runtime();
        if (!mp::enable_mlx_backend && runtime == llm::runner_mlx)
            runtime.clear();

        if (ready.empty())
        {
            reply.set_reply_message(
                "No inference backend is ready. Install llama.cpp or vLLM from Models → Backends.");
            server->Write(reply);
            return;
        }
        if (!runtime.empty() && !ready.contains(runtime))
        {
            reply.set_reply_message(fmt::format(
                "{} backend is not ready. Install it from Models → Backends, then refresh the catalog.",
                runtime));
            server->Write(reply);
            return;
        }

#ifdef Q_OS_MACOS
        const bool unified = true;
#else
        const bool unified = false;
#endif
        const auto limit = request->limit();
        std::vector<ModelSuggestion> models;
        if (request->recommend_only())
        {
            // Catalog "Any" must ask llmfit per ready backend so Top Picks reflect
            // what Launchpad can actually serve — not only the default runner.
            const auto runtimes =
                runtime.empty() ? ordered_ready_runtimes(ready) : std::vector<std::string>{runtime};
            std::unordered_set<std::string> seen_ids;
            for (const auto& rt : runtimes)
            {
                append_unique_models(models,
                                     advisor.recommend(pool.memory_available(),
                                                       pool.host_cpus(),
                                                       rt,
                                                       request->use_case(),
                                                       request->min_fit(),
                                                       limit,
                                                       unified),
                                     seen_ids);
            }
            if (limit > 0 && static_cast<int>(models.size()) > limit)
                models.resize(static_cast<size_t>(limit));
        }
        else
        {
            models = advisor.browse(pool.memory_available(),
                                    pool.host_cpus(),
                                    runtime,
                                    request->use_case(),
                                    request->min_fit(),
                                    request->query(),
                                    limit,
                                    request->offset(),
                                    request->include_too_tight(),
                                    unified);
        }

        for (auto model : models)
        {
            stamp_catalog_model_runtimes(model);
            if (!model_supported_by_ready(model, ready))
                continue;
            *reply.add_models() = model;
        }
    }
    catch (const std::exception& e)
    {
        reply.set_reply_message(e.what());
        mpl::warn(category, "{}", e.what());
    }
    server->Write(reply);
}

void mp::LlmService::log_lifecycle(const std::string& instance_id,
                                   const std::string& level,
                                   const std::string& message)
{
    activity_log.append(instance_id, "lifecycle", level, message);
}

void mp::LlmService::attach_process_logging(const std::string& instance_id, Process* process)
{
    if (!process)
        return;

    auto ingest = [this, instance_id](const QByteArray& chunk, const char* level) {
        for (const auto& line : QString::fromUtf8(chunk).split('\n', Qt::SkipEmptyParts))
        {
            const auto trimmed = line.trimmed();
            if (!trimmed.isEmpty())
                activity_log.append(instance_id, "process", level, trimmed.toStdString());
        }
    };

    // Capture anything already buffered before signal handlers connect.
    ingest(process->read_all_standard_output(), "info");
    ingest(process->read_all_standard_error(), "warn");

    QObject::connect(process,
                     &Process::ready_read_standard_output,
                     this,
                     [process, ingest]() {
                         ingest(process->read_all_standard_output(), "info");
                     });
    QObject::connect(process,
                     &Process::ready_read_standard_error,
                     this,
                     [process, ingest]() {
                         ingest(process->read_all_standard_error(), "warn");
                     });
}

void mp::LlmService::pull_model(
    const PullModelRequest* request,
    grpc::ServerReaderWriterInterface<PullModelReply, PullModelRequest>* server)
{
    const auto model_id = request->model_id();
    log_lifecycle(model_id, "info", "pull started");
    auto monitor = [server, this, model_id](int, int percent) {
        PullModelReply progress;
        auto* lp = progress.mutable_launch_progress();
        lp->set_type(LaunchProgress::IMAGE);
        lp->set_percent_complete(std::to_string(percent));
        server->Write(progress);
        if (percent > 0 && percent % 25 == 0)
            log_lifecycle(model_id, "info", fmt::format("pull {}% complete", percent));
        return true;
    };
    const auto art = ensure_pulled(model_id,
                                   request->quant(),
                                   request->hf_repo(),
                                   monitor,
                                   request->format(),
                                   request->filename());
    PullModelReply reply;
    reply.set_model_id(art.id);
    reply.set_path(art.path);
    reply.set_reply_message("downloaded");
    auto* lp = reply.mutable_launch_progress();
    lp->set_percent_complete("100");
    log_lifecycle(art.id, "info", fmt::format("pull complete: {}", art.path));
    server->Write(reply);
}

void mp::LlmService::list_model_files(
    const ListModelFilesRequest* request,
    grpc::ServerReaderWriterInterface<ListModelFilesReply, ListModelFilesRequest>* server)
{
    ListModelFilesReply reply;
    const auto listed = advisor.list_gguf_files(request->model_id(), request->hf_repo());
    if (!listed)
    {
        throw std::runtime_error(fmt::format(
            "could not list GGUF files for '{}'. Pass a repo id like org/model-GGUF.",
            request->model_id()));
    }
    reply.set_repo(listed->repo);
    reply.set_mmproj_filename(listed->mmproj_filename);
    for (const auto& file : listed->files)
    {
        auto* entry = reply.add_files();
        entry->set_filename(file.filename);
        entry->set_quant(file.quant);
    }
    reply.set_reply_message(fmt::format("{} GGUF file(s)", listed->files.size()));
    server->Write(reply);
}

void mp::LlmService::stop_process_on_thread(Process* process)
{
    if (!process)
        return;
    process->terminate();
    if (!process->wait_for_finished(3000))
        process->kill();
}

void mp::LlmService::stop_process(Process* process)
{
    if (!process)
        return;
    if (QThread::currentThread() == process->thread())
    {
        stop_process_on_thread(process);
        return;
    }

    // Post to the Process QObject (affinity = llama-server runner thread), not
    // process->thread() as a QTimer context. The QThread object lives on the
    // worker that created it, which has no event loop, so that path deadlocks
    // and only the first bulk-unload RPC ever finishes.
    auto done = std::make_shared<std::promise<void>>();
    const auto posted = QMetaObject::invokeMethod(
        process,
        [process, done]() {
            stop_process_on_thread(process);
            try
            {
                done->set_value();
            }
            catch (const std::future_error&)
            {
            }
        },
        Qt::QueuedConnection);
    if (!posted)
    {
        stop_process_on_thread(process);
        return;
    }
    if (done->get_future().wait_for(std::chrono::seconds(8)) == std::future_status::timeout)
    {
        mpl::warn(category, "timed out waiting to stop inference process on its thread");
        stop_process_on_thread(process);
    }
}

void mp::LlmService::load_model(
    const LoadModelRequest* request,
    grpc::ServerReaderWriterInterface<LoadModelReply, LoadModelRequest>* server)
{
    auto runner = std::make_unique<QThread>();
    auto done = std::make_shared<std::promise<void>>();
    auto failure = std::make_shared<std::exception_ptr>();
    auto transferred = std::make_shared<bool>(false);

    // QThread lives on the calling thread; QTimer would never fire there on a
    // QThreadPool worker. Run the load on the runner thread when it starts.
    QObject::connect(
        runner.get(),
        &QThread::started,
        runner.get(),
        [this, request, server, &runner, transferred, failure, done]() {
            try
            {
                load_model_impl(request, server, runner, *transferred);
            }
            catch (...)
            {
                *failure = std::current_exception();
            }
            if (!*transferred)
                QThread::currentThread()->quit();
            done->set_value();
        },
        Qt::DirectConnection);

    runner->start();
    done->get_future().wait();

    if (!*transferred)
    {
        runner->quit();
        runner->wait(5000);
    }

    if (*failure)
        std::rethrow_exception(*failure);

    if (*transferred)
        runner.release();
}

void mp::LlmService::load_model_impl(
    const LoadModelRequest* request,
    grpc::ServerReaderWriterInterface<LoadModelReply, LoadModelRequest>* server,
    std::unique_ptr<QThread>& runner_thread,
    bool& runner_transferred)
{
    const auto model_id = request->model_id();
    const auto runtime = QString::fromStdString(request->runtime()).toLower();
    const bool claim_cloud = runtime == QString::fromUtf8(openai_compat_backend) ||
                             runtime == QStringLiteral("openai_compat");
    if (claim_cloud)
    {
        std::string matched_id;
        std::string openai_id;
        uint32_t port = 0;
        uint64_t memory_claimed = 0;
        {
            std::lock_guard lock{mutex};
            std::optional<std::string> found;
            for (auto& [id, session] : sessions)
            {
                if (!session_is_remote(session))
                    continue;
                if (session.model_id != model_id && session.openai_id != model_id &&
                    session.upstream_model_id != model_id)
                    continue;
                if (found)
                    throw std::runtime_error(fmt::format(
                        "multiple cloud sessions match '{}'; refresh the provider or pick a unique model",
                        model_id));
                found = id;
            }
            if (!found)
                throw std::runtime_error(fmt::format(
                    "no cloud model '{}' is available; add/refresh a provider under Credentials",
                    model_id));
            matched_id = *found;
            auto& session = sessions[matched_id];
            session.intent = request->intent();
            session.intent_role = request->intent_role();
            session.last_used = std::chrono::steady_clock::now();
            openai_id = session.openai_id;
            port = static_cast<uint32_t>(session.port);
            memory_claimed = static_cast<uint64_t>(session.memory.in_bytes());
        }
        persist_sessions();
        LoadModelReply reply;
        reply.set_instance_id(matched_id);
        reply.set_model_id(model_id);
        reply.set_openai_id(openai_id);
        reply.set_port(port);
        reply.set_memory_claimed(memory_claimed);
        reply.set_reply_message(
            fmt::format("claimed cloud model '{}' for intent", model_id));
        log_lifecycle(matched_id,
                      "info",
                      fmt::format("claimed cloud model {} for intent '{}'",
                                  model_id,
                                  request->intent()));
        server->Write(reply);
        return;
    }

    const auto instance_id = mp::utils::make_uuid();
    log_lifecycle(instance_id, "info", fmt::format("load started for {}", model_id));

    auto monitor = [server, this, instance_id](int, int percent) {
        LoadModelReply progress;
        auto* lp = progress.mutable_launch_progress();
        lp->set_percent_complete(std::to_string(percent));
        server->Write(progress);
        if (percent > 0 && percent % 25 == 0)
            log_lifecycle(instance_id, "info", fmt::format("load {}% complete", percent));
        return true;
    };
    const auto art = ensure_pulled(model_id,
                                   request->quant(),
                                   "",
                                   monitor,
                                   llm::format_for_runner(
                                       [&] {
                                           const auto resolved_runner = runners.resolve(request->runtime());
                                           return resolved_runner.runner ? resolved_runner.runner->id()
                                                                         : llm::runner_llamacpp;
                                       }()));
    log_lifecycle(instance_id,
                  "info",
                  fmt::format("using {} artifact at {}", art.format.empty() ? "gguf" : art.format, art.path));
    const auto resolved_runner = runners.resolve(request->runtime());
    if (!resolved_runner.runner)
        throw std::runtime_error("no inference runner available");
    const auto* runner = resolved_runner.runner;
    const auto resolved = resolve_llm_load(*request, runner->uses_gpu(resolved_runner.device));
    const auto ctx = resolved.ctx_size;
    const auto max_tokens = resolved.max_tokens;
    const auto claim = estimate_claim(art,
                                      ctx,
                                      resolved.llama.cache_type_k.toStdString(),
                                      resolved.llama.cache_type_v.toStdString());

    std::string duplicate_warning;
    {
        const LlmLoadFingerprint incoming{model_id,
                                          runner->session_backend_name(resolved_runner.device),
                                          art.path,
                                          ctx,
                                          max_tokens,
                                          resolved.echoed};
        std::lock_guard lock{mutex};
        for (const auto& [_, existing] : sessions)
        {
            if (!session_is_live(existing))
                continue;
            const LlmLoadFingerprint live{existing.model_id,
                                          existing.backend,
                                          existing.path,
                                          existing.ctx_size,
                                          existing.max_tokens,
                                          existing.params};
            if (!llm_loads_identical(incoming, live))
                continue;
            duplicate_warning = fmt::format(
                "warning: an identical instance of '{}' is already running ({}); starting another copy",
                model_id,
                existing.instance_id);
            break;
        }
    }

    auto result = pool.try_claim(instance_id, WorkloadKind::llm, claim, 0);
    if (!result.accepted)
        throw std::runtime_error(result.message);

    LoadedSession session;
    session.instance_id = instance_id;
    session.model_id = model_id;
    session.openai_id = openai_id_for_instance(model_id, instance_id);
    session.backend = runner->session_backend_name(resolved_runner.device);
    session.path = art.path;
    session.port = pick_loopback_port();
    session.memory = claim;
    session.ctx_size = ctx;
    session.max_tokens = max_tokens;
    session.params = resolved.echoed;
    session.intent = request->intent();
    session.intent_role = request->intent_role();

    try
    {
        llm::RunnerLaunchContext launch;
        launch.artifact = art;
        launch.port = session.port;
        launch.openai_id = session.openai_id;
        launch.resolved = resolved;
        launch.data_directory = data_directory;
        launch.device = resolved_runner.device;
        launch.hf_token = hf_token();
        session.process = runner->start(launch);
        session.process->start();
        if (!session.process->wait_for_started(10000))
            throw std::runtime_error("inference backend failed to start");
        session.pid = session.process->process_id();
        // Attach early so boot/load stdout survives readiness wait and dual-writes to disk.
        attach_process_logging(instance_id, session.process.get());
        if (runner->openai_compat())
            ensure_backend_ready(session.process.get(),
                                 session.port,
                                 instance_id,
                                 runner->id(),
                                 runner->id() == llm::runner_mlx,
                                 art.path);
    }
    catch (const std::exception& e)
    {
        if (session.process)
            stop_process_on_thread(session.process.get());
        pool.release(instance_id);
        log_lifecycle(instance_id, "error", fmt::format("load failed: {}", e.what()));
        throw;
    }

    session.runner_thread = std::move(runner_thread);
    runner_transferred = true;

    LoadModelReply reply;
    reply.set_instance_id(instance_id);
    reply.set_model_id(model_id);
    reply.set_openai_id(session.openai_id);
    reply.set_port(static_cast<uint32_t>(session.port));
    reply.set_memory_claimed(static_cast<uint64_t>(session.memory.in_bytes()));
    if (!duplicate_warning.empty() && !result.message.empty())
        reply.set_reply_message(fmt::format("{}; {}", duplicate_warning, result.message));
    else if (!duplicate_warning.empty())
        reply.set_reply_message(duplicate_warning);
    else if (!result.message.empty())
        reply.set_reply_message(result.message);

    if (!duplicate_warning.empty())
        log_lifecycle(instance_id, "warning", duplicate_warning);

    {
        std::lock_guard lock{mutex};
        sessions[instance_id] = std::move(session);
        if (sessions[instance_id].process)
        {
            QObject::connect(sessions[instance_id].process.get(),
                             &Process::finished,
                             this,
                             [this, instance_id](ProcessState) { unload_instance(instance_id); });
        }
    }
    vault.touch(model_id);
    persist_sessions();
    log_lifecycle(instance_id,
                  "info",
                  fmt::format("load complete on port {} as {}", reply.port(), reply.openai_id()));
    server->Write(reply);
}

void mp::LlmService::unload_instance(const std::string& instance_id)
{
    log_lifecycle(instance_id, "info", "unload");
    std::unique_ptr<Process> dying;
    std::unique_ptr<QThread> runner_thread;
    qint64 adopted_pid = 0;
    bool missing = false;
    {
        std::lock_guard lock{mutex};
        auto it = sessions.find(instance_id);
        if (it == sessions.end())
        {
            pool.release(instance_id);
            missing = true;
        }
        else
        {
            dying = std::move(it->second.process);
            runner_thread = std::move(it->second.runner_thread);
            adopted_pid = it->second.pid;
            sessions.erase(it);
            pool.release(instance_id);
        }
    }
    if (missing)
    {
        persist_sessions();
        return;
    }
    keys.revoke_for_instance(instance_id);
    if (dying)
    {
        // Stopping the process emits finished, which was connected back to
        // unload_instance. That re-entry used to persist_sessions() while still
        // holding mutex (deadlock) and blocked the next bulk-unload RPC.
        QObject::disconnect(dying.get(), nullptr, this, nullptr);
        stop_process(dying.get());
    }
    else if (adopted_pid > 0)
        mpu::terminate_pid(adopted_pid);
    if (runner_thread)
    {
        runner_thread->quit();
        runner_thread->wait(5000);
    }
    persist_sessions();
}

void mp::LlmService::unload_all_for_model(const std::string& model_id)
{
    std::vector<std::string> instances;
    {
        std::lock_guard lock{mutex};
        for (const auto& [id, session] : sessions)
        {
            if (session_is_remote(session))
                continue;
            if (session_matches_model(session, model_id))
                instances.push_back(id);
        }
    }
    for (const auto& id : instances)
        unload_instance(id);
}

void mp::LlmService::unload_model(
    const UnloadModelRequest* request,
    grpc::ServerReaderWriterInterface<UnloadModelReply, UnloadModelRequest>* server)
{
    if (!request->instance_id().empty())
    {
        {
            std::lock_guard lock{mutex};
            auto it = sessions.find(request->instance_id());
            if (it != sessions.end() && session_is_remote(it->second))
                throw std::runtime_error(cloud_unload_error);
        }
        unload_instance(request->instance_id());
    }
    else if (!request->model_id().empty())
    {
        bool remote_only = false;
        {
            std::lock_guard lock{mutex};
            bool remote_match = false;
            bool local_match = false;
            for (const auto& [id, session] : sessions)
            {
                if (!session_matches_model(session, request->model_id()))
                    continue;
                if (session_is_remote(session))
                    remote_match = true;
                else
                    local_match = true;
            }
            remote_only = remote_match && !local_match;
        }
        if (remote_only)
            throw std::runtime_error(cloud_unload_error);
        unload_all_for_model(request->model_id());
    }

    UnloadModelReply reply;
    reply.set_model_id(request->model_id());
    reply.set_instance_id(request->instance_id());
    server->Write(reply);
}

void mp::LlmService::list_models(
    const ListModelsRequest*,
    grpc::ServerReaderWriterInterface<ListModelsReply, ListModelsRequest>* server)
{
    reap_dead_sessions();
    ListModelsReply reply;
    std::lock_guard lock{mutex};
    const auto now = std::chrono::steady_clock::now();
    for (auto& [instance_id, session] : sessions)
    {
        // GUI (and other clients) poll list_models while the app is open; count
        // that as activity so idle-unload does not drop models mid-session.
        session.last_used = now;

        auto* info = reply.add_models();
        info->set_instance_id(instance_id);
        info->set_model_id(session.model_id);
        info->set_openai_id(session.openai_id);
        info->set_backend(session.backend);
        info->set_path(session.path);
        info->set_port(static_cast<uint32_t>(session.port));
        info->set_memory_claimed(static_cast<uint64_t>(session.memory.in_bytes()));
        info->set_state(session_is_live(session) ? "loaded" : "stopped");
        info->set_max_tokens(session.max_tokens);
        info->set_ctx_size(session.ctx_size);
        *info->mutable_params() = session.params;
        info->set_intent(session.intent);
        info->set_intent_role(session.intent_role);
        if (!session.provider_id.empty())
            info->set_provider_id(session.provider_id);
        if (!session.upstream_model_id.empty())
            info->set_upstream_model_id(session.upstream_model_id);
        if (!session.owned_by.empty())
            info->set_owned_by(session.owned_by);
    }
    for (const auto& art : vault.list())
    {
        ModelSuggestion cached;
        cached.set_id(art.id);
        cached.set_name(art.id);
        cached.set_best_quant(art.quant);
        cached.set_hf_repo(art.repo);
        cached.set_filename(art.filename);
        const auto size_gb = static_cast<double>(art.size_bytes) / (1024.0 * 1024.0 * 1024.0);
        cached.set_memory_required_gb(size_gb);
        cached.set_disk_size_gb(size_gb);
        cached.set_path(art.path);
        auto fmt = art.format;
        if (fmt.empty())
        {
            const QString path = QString::fromStdString(art.path);
            if (path.endsWith(".gguf", Qt::CaseInsensitive))
                fmt = llm::format_gguf;
            else if (!path.isEmpty())
                // Local vault dirs and HF-style repo ids are not GGUF files.
                // Prefer mlx; explicit format on the artifact wins when set.
                fmt = llm::format_mlx;
            else
                fmt = llm::format_gguf;
        }
        cached.set_format(fmt);
        if (fmt == llm::format_gguf)
        {
            const auto inferred = infer_quant_from_gguf_filename(
                QString::fromStdString(art.filename.empty() ? art.path : art.filename));
            if (!inferred.isEmpty())
                cached.set_best_quant(inferred.toStdString());
        }
        if (fmt == llm::format_mlx)
            cached.add_supported_runtimes(llm::runner_mlx);
        else if (fmt == llm::format_hf)
            cached.add_supported_runtimes(llm::runner_vllm);
        else
            cached.add_supported_runtimes(llm::runner_llamacpp);
        *reply.add_cached() = cached;
    }
    server->Write(reply);
}

void mp::LlmService::list_llm_backends(
    const ListLlmBackendsRequest*,
    grpc::ServerReaderWriterInterface<ListLlmBackendsReply, ListLlmBackendsRequest>* server)
{
    const auto selected = runners.select_default();
    const auto selected_id =
        selected.runner ? selected.runner->session_backend_name(selected.device) : llm::runner_llamacpp;
    ListLlmBackendsReply reply;
    reply.set_selected_backend(selected_id);
    for (const auto& row : llm::probe_backends(selected_id, llm::managed_tools_root(data_directory)))
    {
        auto* out = reply.add_backends();
        out->set_id(row.id);
        out->set_name(row.name);
        out->set_status(row.status);
        out->set_detail(row.detail);
        out->set_binary_path(row.binary_path);
        out->set_install_hint(row.install_hint);
        out->set_required(row.required);
        out->set_active(row.active);
        out->set_installable(row.installable);
    }
    server->Write(reply);
}

void mp::LlmService::install_llm_backend(
    const InstallLlmBackendRequest* request,
    grpc::ServerReaderWriterInterface<InstallLlmBackendReply, InstallLlmBackendRequest>* server)
{
    const auto backend_id = QString::fromStdString(request->backend_id());
    llm::RuntimeInstaller installer{downloader, data_directory};

    // Coalesce chatty process log lines (~10 writes/s) while flushing status/percent
    // changes immediately.
    struct ProgressStreamState
    {
        std::string pending_log;
        std::string last_status;
        int last_percent{-1};
        QString last_path;
        std::string last_message;
        std::chrono::steady_clock::time_point last_log_flush{};
    };
    auto stream = std::make_shared<ProgressStreamState>();

    auto write_reply = [server, backend_id](const ProgressStreamState& s, std::string log_line) {
        InstallLlmBackendReply reply;
        reply.set_backend_id(backend_id.toStdString());
        reply.set_status(s.last_status);
        reply.set_progress_percent(s.last_percent < 0 ? 0 : s.last_percent);
        reply.set_binary_path(s.last_path.toStdString());
        if (!s.last_message.empty())
            reply.set_reply_message(s.last_message);
        if (!log_line.empty())
            reply.set_log_line(std::move(log_line));
        server->Write(reply);
    };

    auto on_progress = [stream, write_reply](const llm::InstallProgress& progress) {
        const bool status_changed = progress.status != stream->last_status ||
                                    progress.percent != stream->last_percent ||
                                    progress.binary_path != stream->last_path ||
                                    (!progress.message.empty() && progress.message != stream->last_message);

        if (!progress.status.empty())
            stream->last_status = progress.status;
        stream->last_percent = progress.percent;
        if (!progress.binary_path.isEmpty())
            stream->last_path = progress.binary_path;
        if (!progress.message.empty())
            stream->last_message = progress.message;

        if (!progress.log_line.empty())
        {
            if (!stream->pending_log.empty())
                stream->pending_log.push_back('\n');
            stream->pending_log.append(progress.log_line);
        }

        const auto now = std::chrono::steady_clock::now();
        const bool log_due = !stream->pending_log.empty() &&
                             (stream->last_log_flush.time_since_epoch().count() == 0 ||
                              now - stream->last_log_flush >= std::chrono::milliseconds{100});

        if (status_changed || log_due)
        {
            std::string log;
            if (log_due)
            {
                log = std::move(stream->pending_log);
                stream->pending_log.clear();
                stream->last_log_flush = now;
            }
            write_reply(*stream, std::move(log));
        }
    };

    const auto path = installer.install(backend_id, on_progress);
    if (!stream->pending_log.empty())
        write_reply(*stream, std::move(stream->pending_log));

    InstallLlmBackendReply reply;
    reply.set_backend_id(backend_id.toStdString());
    reply.set_status("ready");
    reply.set_progress_percent(100);
    reply.set_binary_path(path.toStdString());
    reply.set_reply_message("installed");
    server->Write(reply);
}

void mp::LlmService::create_api_key(
    const CreateApiKeyRequest* request,
    grpc::ServerReaderWriterInterface<CreateApiKeyReply, CreateApiKeyRequest>* server)
{
    std::vector<std::string> instance_ids;
    if (request->instance_ids_size() > 0)
    {
        for (const auto& id : request->instance_ids())
        {
            if (!id.empty())
                instance_ids.push_back(id);
        }
    }
    else if (!request->instance_id().empty())
        instance_ids.push_back(request->instance_id());

    if (!instance_ids.empty())
    {
        std::lock_guard lock{mutex};
        for (const auto& instance_id : instance_ids)
        {
            if (sessions.find(instance_id) == sessions.end())
                throw std::runtime_error(fmt::format("unknown instance '{}'", instance_id));
        }
    }

    const auto created = keys.create(request->label(), instance_ids);
    CreateApiKeyReply reply;
    reply.set_id(created.record.id);
    reply.set_prefix(created.record.prefix);
    reply.set_secret(created.secret);
    reply.set_label(created.record.label);
    for (const auto& id : created.record.instance_ids)
        reply.add_instance_ids(id);
    if (!created.record.instance_ids.empty())
    {
        reply.set_instance_id(created.record.instance_ids.front());
        std::lock_guard lock{mutex};
        if (auto it = sessions.find(created.record.instance_ids.front()); it != sessions.end())
        {
            reply.set_model_id(it->second.model_id);
            reply.set_openai_id(it->second.openai_id);
        }
    }
    server->Write(reply);
}

void mp::LlmService::list_api_keys(
    const ListApiKeysRequest*,
    grpc::ServerReaderWriterInterface<ListApiKeysReply, ListApiKeysRequest>* server)
{
    ListApiKeysReply reply;
    std::lock_guard lock{mutex};
    for (const auto& key : keys.list())
    {
        auto* info = reply.add_keys();
        info->set_id(key.id);
        info->set_prefix(key.prefix);
        info->set_label(key.label);
        info->set_created_at(key.created_at);
        for (const auto& id : key.instance_ids)
            info->add_instance_ids(id);
        if (!key.instance_ids.empty())
        {
            info->set_instance_id(key.instance_ids.front());
            if (auto it = sessions.find(key.instance_ids.front()); it != sessions.end())
            {
                info->set_model_id(it->second.model_id);
                info->set_openai_id(it->second.openai_id);
            }
        }
    }
    server->Write(reply);
}

void mp::LlmService::update_api_key(
    const UpdateApiKeyRequest* request,
    grpc::ServerReaderWriterInterface<UpdateApiKeyReply, UpdateApiKeyRequest>* server)
{
    if (request->id().empty())
        throw std::runtime_error("API key id is required");

    std::vector<std::string> instance_ids;
    if (request->update_instance_ids())
    {
        for (const auto& id : request->instance_ids())
        {
            if (!id.empty())
                instance_ids.push_back(id);
        }
    }

    const auto updated = keys.update(request->id(),
                                     request->label(),
                                     instance_ids,
                                     request->update_label(),
                                     request->update_instance_ids());
    if (!updated)
        throw std::runtime_error("API key not found");

    UpdateApiKeyReply reply;
    auto* info = reply.mutable_key();
    info->set_id(updated->id);
    info->set_prefix(updated->prefix);
    info->set_label(updated->label);
    info->set_created_at(updated->created_at);
    for (const auto& id : updated->instance_ids)
        info->add_instance_ids(id);
    if (!updated->instance_ids.empty())
    {
        info->set_instance_id(updated->instance_ids.front());
        std::lock_guard lock{mutex};
        if (auto it = sessions.find(updated->instance_ids.front()); it != sessions.end())
        {
            info->set_model_id(it->second.model_id);
            info->set_openai_id(it->second.openai_id);
        }
    }
    server->Write(reply);
}

void mp::LlmService::revoke_api_key(
    const RevokeApiKeyRequest* request,
    grpc::ServerReaderWriterInterface<RevokeApiKeyReply, RevokeApiKeyRequest>* server)
{
    const auto id = request->id().empty() ? request->prefix() : request->id();
    const bool ok = keys.revoke_by_id(id) || keys.revoke_by_prefix(id);
    if (!ok)
        throw std::runtime_error("API key not found");
    RevokeApiKeyReply reply;
    reply.set_id(id);
    server->Write(reply);
}

void mp::LlmService::verify_api_key(
    const VerifyApiKeyRequest* request,
    grpc::ServerReaderWriterInterface<VerifyApiKeyReply, VerifyApiKeyRequest>* server)
{
    VerifyApiKeyReply reply;
    if (auto rec = keys.verify(request->secret()))
    {
        reply.set_valid(true);
        reply.set_id(rec->id);
        reply.set_prefix(rec->prefix);
        for (const auto& id : rec->instance_ids)
            reply.add_instance_ids(id);
        if (!rec->instance_ids.empty())
            reply.set_instance_id(rec->instance_ids.front());
    }
    else
        reply.set_valid(false);
    server->Write(reply);
}

void mp::LlmService::touch_model(
    const TouchModelRequest* request,
    grpc::ServerReaderWriterInterface<TouchModelReply, TouchModelRequest>* server)
{
    std::string resolved_instance;
    {
        std::lock_guard lock{mutex};
        if (!request->instance_id().empty())
        {
            if (auto it = sessions.find(request->instance_id()); it != sessions.end())
            {
                it->second.last_used = std::chrono::steady_clock::now();
                resolved_instance = request->instance_id();
            }
        }
        else if (!request->model_id().empty())
        {
            const auto& lookup = request->model_id();
            if (auto it = sessions.find(lookup); it != sessions.end())
            {
                it->second.last_used = std::chrono::steady_clock::now();
                resolved_instance = lookup;
            }
            else
            {
                std::optional<std::string> by_model_id;
                for (auto& [id, session] : sessions)
                {
                    if (session.openai_id == lookup)
                    {
                        session.last_used = std::chrono::steady_clock::now();
                        resolved_instance = id;
                        break;
                    }
                    if (session.model_id == lookup)
                    {
                        if (by_model_id)
                        {
                            by_model_id.reset();
                            break;
                        }
                        by_model_id = id;
                    }
                }
                if (resolved_instance.empty() && by_model_id)
                {
                    sessions[*by_model_id].last_used = std::chrono::steady_clock::now();
                    resolved_instance = *by_model_id;
                }
            }
        }
    }

    if (!resolved_instance.empty() && !request->method().empty())
    {
        const auto level = request->status_code() >= 400 ? "warn" : "info";
        activity_log.append(resolved_instance,
                            "gateway",
                            level,
                            fmt::format("{} {} {}",
                                        request->method(),
                                        request->path(),
                                        request->status_code()));
    }

    TouchModelReply reply;
    server->Write(reply);
}

void mp::LlmService::stream_model_logs(
    const StreamModelLogsRequest* request,
    grpc::ServerReaderWriterInterface<StreamModelLogsReply, StreamModelLogsRequest>* server)
{
    std::string instance_id = request->instance_id();
    if (instance_id.empty())
    {
        if (request->model_id().empty())
            throw std::runtime_error("instance_id is required");

        std::lock_guard lock{mutex};
        std::optional<std::string> match;
        for (const auto& [id, session] : sessions)
        {
            if (session.model_id == request->model_id() || id == request->model_id() ||
                session.openai_id == request->model_id())
            {
                if (match)
                    throw std::runtime_error(
                        "multiple instances match model_id; specify instance_id");
                match = id;
            }
        }
        if (!match)
            throw std::runtime_error(fmt::format("no loaded instance matches '{}'",
                                                 request->model_id()));
        instance_id = *match;
    }

    for (const auto& entry : activity_log.snapshot(instance_id))
    {
        StreamModelLogsReply reply;
        *reply.mutable_entry() = entry;
        if (!server->Write(reply))
            return;
    }

    std::mutex wait_mutex;
    std::condition_variable cv;
    std::deque<ModelActivityEntry> pending;
    const auto sub_id = activity_log.subscribe(instance_id, [&](const ModelActivityEntry& entry) {
        {
            std::lock_guard lock{wait_mutex};
            pending.push_back(entry);
        }
        cv.notify_one();
    });

    while (true)
    {
        std::unique_lock lock{wait_mutex};
        cv.wait_for(lock, std::chrono::seconds(30));
        if (pending.empty())
        {
            lock.unlock();
            StreamModelLogsReply heartbeat;
            if (!server->Write(heartbeat))
            {
                activity_log.unsubscribe(sub_id);
                return;
            }
            continue;
        }
        while (!pending.empty())
        {
            StreamModelLogsReply reply;
            *reply.mutable_entry() = pending.front();
            pending.pop_front();
            lock.unlock();
            if (!server->Write(reply))
            {
                activity_log.unsubscribe(sub_id);
                return;
            }
            lock.lock();
        }
    }
}

void mp::LlmService::delete_model(
    const DeleteModelRequest* request,
    grpc::ServerReaderWriterInterface<DeleteModelReply, DeleteModelRequest>* server)
{
    const auto model_id = request->model_id();
    if (model_id.empty())
        throw std::runtime_error("model_id is required");

    if (is_loaded(model_id))
        unload_all_for_model(model_id);

    const auto artifact = vault.find(model_id);
    if (!artifact)
        throw std::runtime_error(fmt::format("model '{}' is not downloaded", model_id));

    const auto freed = static_cast<uint64_t>(std::max(0LL, artifact->size_bytes));
    if (!vault.remove(model_id))
        throw std::runtime_error(fmt::format("failed to delete model '{}'", model_id));

    DeleteModelReply reply;
    reply.set_model_id(model_id);
    reply.set_freed_bytes(freed);
    server->Write(reply);
}

bool mp::LlmService::is_loaded(const std::string& model_id) const
{
    std::lock_guard lock{mutex};
    for (const auto& [_, session] : sessions)
    {
        if (session.model_id == model_id)
            return true;
    }
    return false;
}

bool mp::LlmService::has_instance(const std::string& instance_id) const
{
    std::lock_guard lock{mutex};
    return sessions.find(instance_id) != sessions.end();
}

std::optional<mp::LoadedModelInfo> mp::LlmService::instance_info(const std::string& instance_id) const
{
    std::lock_guard lock{mutex};
    auto it = sessions.find(instance_id);
    if (it == sessions.end())
        return std::nullopt;

    LoadedModelInfo info;
    fill_loaded_model_info(&info, it->second);
    return info;
}

std::optional<mp::LoadedSession*> mp::LlmService::session_by_openai_id(const std::string& openai_id)
{
    std::lock_guard lock{mutex};
    for (auto& [_, session] : sessions)
    {
        if (session.openai_id == openai_id)
            return &session;
    }
    return std::nullopt;
}

void mp::LlmService::reap_dead_sessions()
{
    std::vector<std::string> dead;
    {
        std::lock_guard lock{mutex};
        for (const auto& [id, session] : sessions)
        {
            if (!session_is_live(session))
                dead.push_back(id);
        }
    }
    for (const auto& id : dead)
        unload_instance(id);
}

void mp::LlmService::idle_unload_tick()
{
    const auto ttl = idle_ttl();
    if (ttl.count() <= 0)
        return;
    const auto now = std::chrono::steady_clock::now();
    std::vector<std::string> idle;
    {
        std::lock_guard lock{mutex};
        for (const auto& [id, session] : sessions)
        {
            if (session_is_remote(session))
                continue;
            if (now - session.last_used > ttl)
                idle.push_back(id);
        }
    }
    for (const auto& id : idle)
    {
        mpl::info(category, "idle-unloading model '{}'", id);
        unload_instance(id);
    }
}

void mp::LlmService::persist_sessions() const
{
    QJsonArray array;
    {
        std::lock_guard lock{mutex};
        for (const auto& [id, session] : sessions)
        {
            QJsonObject obj;
            obj["instance_id"] = QString::fromStdString(session.instance_id);
            obj["model_id"] = QString::fromStdString(session.model_id);
            obj["openai_id"] = QString::fromStdString(session.openai_id);
            obj["backend"] = QString::fromStdString(session.backend);
            obj["path"] = QString::fromStdString(session.path);
            obj["port"] = session.port;
            obj["pid"] = session.pid;
            obj["memory_bytes"] = static_cast<qint64>(session.memory.in_bytes());
            obj["max_tokens"] = session.max_tokens;
            obj["ctx_size"] = session.ctx_size;
            const auto params = llm_load_params_to_json(session.params);
            if (!params.isEmpty())
                obj["params"] = params;
            obj["intent"] = QString::fromStdString(session.intent);
            obj["intent_role"] = QString::fromStdString(session.intent_role);
            if (!session.provider_id.empty())
                obj["provider_id"] = QString::fromStdString(session.provider_id);
            if (!session.upstream_model_id.empty())
                obj["upstream_model_id"] = QString::fromStdString(session.upstream_model_id);
            if (!session.owned_by.empty())
                obj["owned_by"] = QString::fromStdString(session.owned_by);
            array.append(obj);
        }
    }
    QJsonObject root;
    root["sessions"] = array;
    MP_FILEOPS.write_transactionally(
        sessions_file(),
        QJsonDocument{root}.toJson(QJsonDocument::Compact));
}

QString mp::LlmService::sessions_file() const
{
    return QDir{data_directory}.filePath("llm-sessions.json");
}

bool mp::LlmService::session_is_remote(const LoadedSession& session) const
{
    return session.backend == openai_compat_backend || !session.provider_id.empty();
}

bool mp::LlmService::session_is_live(const LoadedSession& session) const
{
    if (session_is_remote(session))
        return providers.get(session.provider_id).has_value();
    if (session.process && session.process->running())
        return true;
    return mpu::pid_is_alive(session.pid);
}

void mp::LlmService::restore_session(LoadedSession session)
{
    if (session.instance_id.empty())
        return;
    const auto id = session.instance_id;
    if (session_is_remote(session))
    {
        session.memory = MemorySize::from_bytes(0);
        session.port = 0;
        session.pid = 0;
        mpl::info(category,
                  "Restored remote LLM instance '{}' ({}) provider={}",
                  id,
                  session.openai_id,
                  session.provider_id);
        activity_log.hydrate(id);
        log_lifecycle(id, "info", "remote session restored from disk");
        std::lock_guard lock{mutex};
        sessions[id] = std::move(session);
        return;
    }
    const auto claim = session.memory.in_bytes() > 0 ? session.memory : MemorySize{"512M"};
    pool.force_claim(id, WorkloadKind::llm, claim, 0);
    session.memory = claim;
    mpl::info(category,
              "Restored LLM instance '{}' ({}) pid={} port={}",
              id,
              session.openai_id,
              session.pid,
              session.port);
    activity_log.hydrate(id);
    log_lifecycle(id,
                  "info",
                  fmt::format("session restored (pid={} port={}); prior activity loaded from disk",
                              session.pid,
                              session.port));
    std::lock_guard lock{mutex};
    sessions[id] = std::move(session);
}

void mp::LlmService::fill_loaded_model_info(LoadedModelInfo* info, const LoadedSession& session) const
{
    info->set_instance_id(session.instance_id);
    info->set_model_id(session.model_id);
    info->set_openai_id(session.openai_id);
    info->set_backend(session.backend);
    info->set_path(session.path);
    info->set_port(static_cast<uint32_t>(session.port));
    info->set_memory_claimed(static_cast<uint64_t>(session.memory.in_bytes()));
    info->set_state(session_is_live(session) ? "loaded" : "stopped");
    info->set_max_tokens(session.max_tokens);
    info->set_ctx_size(session.ctx_size);
    *info->mutable_params() = session.params;
    info->set_intent(session.intent);
    info->set_intent_role(session.intent_role);
    if (!session.provider_id.empty())
        info->set_provider_id(session.provider_id);
    if (!session.upstream_model_id.empty())
        info->set_upstream_model_id(session.upstream_model_id);
    if (!session.owned_by.empty())
        info->set_owned_by(session.owned_by);
}

mp::LlmProviderInfo mp::LlmService::provider_info(const LlmProviderRecord& rec) const
{
    LlmProviderInfo info;
    info.set_id(rec.id);
    info.set_label(rec.label);
    info.set_preset(rec.preset);
    info.set_base_url(rec.base_url);
    info.set_key_prefix(rec.key_prefix);
    for (const auto& pat : rec.include)
        info.add_include(pat);
    for (const auto& pat : rec.exclude)
        info.add_exclude(pat);
    info.set_created_at(rec.created_at);
    info.set_last_refresh_at(rec.last_refresh_at);
    int count = 0;
    {
        std::lock_guard lock{mutex};
        for (const auto& [_, session] : sessions)
        {
            if (session.provider_id == rec.id)
                ++count;
        }
    }
    info.set_model_count(count);
    return info;
}

void mp::LlmService::remove_provider_sessions(const std::string& provider_id)
{
    std::vector<std::string> ids;
    {
        std::lock_guard lock{mutex};
        for (const auto& [id, session] : sessions)
        {
            if (session.provider_id == provider_id)
                ids.push_back(id);
        }
    }
    for (const auto& id : ids)
        unload_instance(id);
}

mp::LlmService::RefreshResult mp::LlmService::refresh_provider_models(const LlmProviderRecord& provider)
{
    const auto upstream = openai_compat_list_models(provider.base_url, provider.api_key);
    std::vector<OpenAiCompatModel> filtered;
    filtered.reserve(upstream.size());
    for (const auto& model : upstream)
    {
        if (llm_provider_id_matches(model.id, provider.include, provider.exclude))
            filtered.push_back(model);
    }

    RefreshResult result;
    std::unordered_map<std::string, std::string> existing_by_upstream; // upstream -> instance_id
    {
        std::lock_guard lock{mutex};
        for (const auto& [id, session] : sessions)
        {
            if (session.provider_id != provider.id)
                continue;
            const auto key =
                session.upstream_model_id.empty() ? session.openai_id : session.upstream_model_id;
            existing_by_upstream[key] = id;
        }

        std::unordered_set<std::string> keep_upstream;
        for (const auto& model : filtered)
        {
            keep_upstream.insert(model.id);
            auto it = existing_by_upstream.find(model.id);
            if (it != existing_by_upstream.end())
            {
                auto& session = sessions[it->second];
                session.openai_id = model.id;
                session.model_id = model.id;
                session.upstream_model_id = model.id;
                session.owned_by =
                    model.owned_by.empty()
                        ? (provider.label.empty() ? provider.preset : provider.label)
                        : model.owned_by;
                session.backend = openai_compat_backend;
                session.last_used = std::chrono::steady_clock::now();
                ++result.kept;
                continue;
            }

            // Reject duplicate openai_id owned by another provider/session.
            bool conflict = false;
            for (const auto& [other_id, other] : sessions)
            {
                if (other.openai_id == model.id && other.provider_id != provider.id)
                {
                    conflict = true;
                    break;
                }
            }
            if (conflict)
            {
                mpl::warn(category,
                          "skipping model '{}' from provider '{}': openai_id already exposed",
                          model.id,
                          provider.id);
                continue;
            }

            LoadedSession session;
            session.instance_id = QUuid::createUuid().toString(QUuid::WithoutBraces).toStdString();
            session.model_id = model.id;
            session.openai_id = model.id;
            session.backend = openai_compat_backend;
            session.provider_id = provider.id;
            session.upstream_model_id = model.id;
            session.owned_by = model.owned_by.empty()
                                   ? (provider.label.empty() ? provider.preset : provider.label)
                                   : model.owned_by;
            session.ctx_size = 0;
            session.max_tokens = 0;
            sessions[session.instance_id] = std::move(session);
            ++result.added;
        }

        std::vector<std::string> to_remove;
        for (const auto& [upstream_id, instance_id] : existing_by_upstream)
        {
            if (!keep_upstream.contains(upstream_id))
                to_remove.push_back(instance_id);
        }
        for (const auto& id : to_remove)
        {
            sessions.erase(id);
            keys.revoke_for_instance(id);
            ++result.removed;
        }
    }

    providers.touch_refresh(provider.id);
    persist_sessions();
    return result;
}

void mp::LlmService::create_llm_provider(
    const CreateLlmProviderRequest* request,
    grpc::ServerReaderWriterInterface<CreateLlmProviderReply, CreateLlmProviderRequest>* server)
{
    std::vector<std::string> include;
    for (const auto& pat : request->include())
        if (!pat.empty())
            include.push_back(pat);
    std::vector<std::string> exclude;
    for (const auto& pat : request->exclude())
        if (!pat.empty())
            exclude.push_back(pat);

    const auto created = providers.create(request->label(),
                                          request->preset(),
                                          request->base_url(),
                                          request->api_key(),
                                          include,
                                          exclude);

    RefreshResult refresh;
    // Discover models immediately so they appear in list_models / /v1/models.
    refresh = refresh_provider_models(created);

    auto updated = providers.get(created.id).value_or(created);
    CreateLlmProviderReply reply;
    *reply.mutable_provider() = provider_info(updated);
    reply.set_models_added(refresh.added);
    reply.set_log_line(fmt::format("provider '{}' ready ({} models)",
                                   updated.label,
                                   reply.provider().model_count()));
    server->Write(reply);
}

void mp::LlmService::list_llm_providers(
    const ListLlmProvidersRequest*,
    grpc::ServerReaderWriterInterface<ListLlmProvidersReply, ListLlmProvidersRequest>* server)
{
    ListLlmProvidersReply reply;
    for (const auto& rec : providers.list())
        *reply.add_providers() = provider_info(rec);
    server->Write(reply);
}

void mp::LlmService::update_llm_provider(
    const UpdateLlmProviderRequest* request,
    grpc::ServerReaderWriterInterface<UpdateLlmProviderReply, UpdateLlmProviderRequest>* server)
{
    if (request->id().empty())
        throw std::runtime_error("provider id is required");

    std::vector<std::string> include;
    for (const auto& pat : request->include())
        if (!pat.empty())
            include.push_back(pat);
    std::vector<std::string> exclude;
    for (const auto& pat : request->exclude())
        if (!pat.empty())
            exclude.push_back(pat);

    auto updated = providers.update(request->id(),
                                    request->label(),
                                    request->update_label(),
                                    request->base_url(),
                                    request->update_base_url(),
                                    request->api_key(),
                                    request->update_api_key(),
                                    include,
                                    request->update_include(),
                                    exclude,
                                    request->update_exclude());
    if (!updated)
        throw std::runtime_error(fmt::format("unknown provider '{}'", request->id()));

    RefreshResult refresh;
    if (request->refresh() || request->update_include() || request->update_exclude() ||
        request->update_api_key() || request->update_base_url())
    {
        refresh = refresh_provider_models(*updated);
        updated = providers.get(request->id());
    }

    UpdateLlmProviderReply reply;
    *reply.mutable_provider() = provider_info(*updated);
    reply.set_models_added(refresh.added);
    server->Write(reply);
}

void mp::LlmService::delete_llm_provider(
    const DeleteLlmProviderRequest* request,
    grpc::ServerReaderWriterInterface<DeleteLlmProviderReply, DeleteLlmProviderRequest>* server)
{
    if (request->id().empty())
        throw std::runtime_error("provider id is required");

    int removed = 0;
    {
        std::lock_guard lock{mutex};
        std::vector<std::string> ids;
        for (const auto& [id, session] : sessions)
        {
            if (session.provider_id == request->id())
                ids.push_back(id);
        }
        removed = static_cast<int>(ids.size());
        for (const auto& id : ids)
        {
            sessions.erase(id);
            keys.revoke_for_instance(id);
        }
    }
    if (!providers.remove(request->id()))
        throw std::runtime_error(fmt::format("unknown provider '{}'", request->id()));
    persist_sessions();

    DeleteLlmProviderReply reply;
    reply.set_id(request->id());
    reply.set_models_removed(removed);
    server->Write(reply);
}

void mp::LlmService::refresh_llm_provider(
    const RefreshLlmProviderRequest* request,
    grpc::ServerReaderWriterInterface<RefreshLlmProviderReply, RefreshLlmProviderRequest>* server)
{
    if (request->id().empty())
        throw std::runtime_error("provider id is required");
    auto provider = providers.get(request->id());
    if (!provider)
        throw std::runtime_error(fmt::format("unknown provider '{}'", request->id()));

    const auto refresh = refresh_provider_models(*provider);
    provider = providers.get(request->id());

    RefreshLlmProviderReply reply;
    *reply.mutable_provider() = provider_info(*provider);
    reply.set_models_added(refresh.added);
    reply.set_models_removed(refresh.removed);
    reply.set_models_kept(refresh.kept);
    reply.set_log_line(
        fmt::format("refreshed: +{} -{} ={}", refresh.added, refresh.removed, refresh.kept));
    server->Write(reply);
}

void mp::LlmService::resolve_model_route(
    const ResolveModelRouteRequest* request,
    grpc::ServerReaderWriterInterface<ResolveModelRouteReply, ResolveModelRouteRequest>* server)
{
    if (request->instance_id().empty())
        throw std::runtime_error("instance_id is required");

    std::lock_guard lock{mutex};
    auto it = sessions.find(request->instance_id());
    if (it == sessions.end())
        throw std::runtime_error(fmt::format("unknown instance '{}'", request->instance_id()));

    const auto& session = it->second;
    ResolveModelRouteReply reply;
    reply.set_instance_id(session.instance_id);
    reply.set_openai_id(session.openai_id);
    reply.set_max_tokens(session.max_tokens);
    reply.set_owned_by(session.owned_by.empty() ? "elp" : session.owned_by);

    if (session_is_remote(session))
    {
        auto provider = providers.get(session.provider_id);
        if (!provider)
            throw std::runtime_error(
                fmt::format("provider '{}' missing for instance '{}'",
                            session.provider_id,
                            session.instance_id));
        reply.set_kind(openai_compat_backend);
        reply.set_base_url(provider->base_url);
        reply.set_upstream_model_id(session.upstream_model_id.empty() ? session.openai_id
                                                                      : session.upstream_model_id);
        reply.set_api_key(provider->api_key);
        reply.set_port(0);
    }
    else
    {
        reply.set_kind("local");
        reply.set_port(static_cast<uint32_t>(session.port));
        // mlx_lm has no --alias; clients send openai_id but the server expects --model.
        if (session.backend == llm::runner_mlx ||
            QString::fromStdString(session.backend).startsWith(QStringLiteral("mlx")))
            reply.set_upstream_model_id(session.path);
    }
    server->Write(reply);
}
