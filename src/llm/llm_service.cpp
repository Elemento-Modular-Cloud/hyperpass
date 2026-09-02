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
#include "llama_server_process_spec.h"
#include "mlx_server_process_spec.h"

#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/platform.h>
#include <multipass/process/simple_process_spec.h>
#include <multipass/settings/settings.h>
#include <multipass/utils.h>

#include <QEventLoop>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTcpServer>
#include <QThread>
#include <QTimer>
#include <QUrl>

#include <algorithm>
#include <cctype>
#include <condition_variable>
#include <deque>
#include <future>
#include <stdexcept>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "llm";

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

#ifndef Q_OS_MACOS
bool cuda_present()
{
    return !QStandardPaths::findExecutable("nvidia-smi").isEmpty();
}
#endif
} // namespace

mp::LlmService::LlmService(ResourcePool& pool, URLDownloader& downloader, Path data_directory)
    : pool{pool}, vault{data_directory, downloader}, keys{data_directory}, data_directory{data_directory}
{
    idle_timer.setInterval(15000);
    QObject::connect(&idle_timer, &QTimer::timeout, this, [this] { idle_unload_tick(); });
    idle_timer.start();
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
    // Sessions are not persisted across daemon restarts; claims live only while processes run.
}

mp::LlmService::BackendKind mp::LlmService::select_backend() const
{
    QString setting = "auto";
    try
    {
        setting = MP_SETTINGS.get(mp::llm_backend_key).toLower();
    }
    catch (const std::exception&)
    {
    }

    if (setting == "mlx")
        return BackendKind::mlx;
    if (setting == "cuda")
        return BackendKind::llamacpp_cuda;
    if (setting == "llamacpp")
    {
#ifdef Q_OS_MACOS
        return BackendKind::llamacpp_metal;
#else
        return cuda_present() ? BackendKind::llamacpp_cuda : BackendKind::llamacpp_cpu;
#endif
    }

#ifdef Q_OS_MACOS
    return BackendKind::llamacpp_metal;
#else
    if (cuda_present())
        return BackendKind::llamacpp_cuda;
    return BackendKind::llamacpp_cpu;
#endif
}

std::string mp::LlmService::backend_name(BackendKind kind) const
{
    switch (kind)
    {
    case BackendKind::mlx:
        return "mlx";
    case BackendKind::llamacpp_cuda:
        return "llamacpp-cuda";
    case BackendKind::llamacpp_metal:
        return "llamacpp-metal";
    case BackendKind::llamacpp_cpu:
    default:
        return "llamacpp";
    }
}

int mp::LlmService::gpu_layers(BackendKind kind) const
{
    switch (kind)
    {
    case BackendKind::llamacpp_metal:
    case BackendKind::llamacpp_cuda:
        return 99;
    default:
        return 0;
    }
}

mp::MemorySize mp::LlmService::estimate_claim(const ModelArtifact& artifact, int ctx_size) const
{
    const auto file_bytes = std::max(0LL, artifact.size_bytes);
    const auto kv = static_cast<long long>(std::max(ctx_size, 2048)) * 2LL * 1024 * 1024 / 8;
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

bool mp::LlmService::wait_until_ready(int port) const
{
    QNetworkAccessManager manager;
    const QUrl url{QStringLiteral("http://127.0.0.1:%1/v1/models").arg(port)};
    for (int i = 0; i < 60; ++i)
    {
        QEventLoop loop;
        QTimer timeout;
        timeout.setSingleShot(true);
        timeout.setInterval(1000);
        auto* reply = manager.get(QNetworkRequest{url});
        QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
        QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
        timeout.start();
        loop.exec();
        const bool ok = reply->error() == QNetworkReply::NoError;
        reply->deleteLater();
        if (ok)
            return true;
        QEventLoop pause;
        QTimer::singleShot(500, &pause, &QEventLoop::quit);
        pause.exec();
    }
    return false;
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
        "checkpoints; Hyperpass downloads a matching GGUF via `llmfit download --list`. "
        "Try a GGUF repo id such as bartowski/Qwen2.5-Coder-7B-Instruct-GGUF",
        model_id));
}

mp::ModelArtifact mp::LlmService::ensure_pulled(const std::string& model_id,
                                                const std::string& quant,
                                                const std::string& hf_repo,
                                                const ProgressMonitor& monitor)
{
    if (auto existing = vault.find(model_id))
        return *existing;

    const auto resolved = resolve_or_throw(model_id, quant, hf_repo);
    if (resolved.filename.empty())
        throw std::runtime_error("llmfit listed the repo but did not name a GGUF file");
    return vault.pull(model_id, resolved.repo, resolved.filename, quant, hf_token(), monitor);
}

void mp::LlmService::find_models(
    const FindModelsRequest* request,
    grpc::ServerReaderWriterInterface<FindModelsReply, FindModelsRequest>* server)
{
    FindModelsReply reply;
    try
    {
        auto runtime = request->runtime();
        if (runtime.empty() && request->recommend_only())
        {
            runtime = select_backend() == BackendKind::mlx ? "mlx" : "llamacpp";
        }
#ifdef Q_OS_MACOS
        const bool unified = true;
#else
        const bool unified = false;
#endif
        const auto models = request->recommend_only()
                                ? advisor.recommend(pool.memory_available(),
                                                    pool.host_cpus(),
                                                    runtime,
                                                    request->use_case(),
                                                    request->min_fit(),
                                                    request->limit(),
                                                    unified)
                                : advisor.browse(pool.memory_available(),
                                                 pool.host_cpus(),
                                                 runtime,
                                                 request->use_case(),
                                                 request->min_fit(),
                                                 request->query(),
                                                 request->limit(),
                                                 request->offset(),
                                                 request->include_too_tight(),
                                                 unified);
        for (const auto& model : models)
            *reply.add_models() = model;
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

    QObject::connect(process,
                     &Process::ready_read_standard_output,
                     this,
                     [this, instance_id, process]() {
                         const auto chunk = process->read_all_standard_output();
                         for (const auto& line :
                              QString::fromUtf8(chunk).split('\n', Qt::SkipEmptyParts))
                         {
                             const auto trimmed = line.trimmed();
                             if (!trimmed.isEmpty())
                                 activity_log.append(instance_id, "process", "info", trimmed.toStdString());
                         }
                     });
    QObject::connect(process,
                     &Process::ready_read_standard_error,
                     this,
                     [this, instance_id, process]() {
                         const auto chunk = process->read_all_standard_error();
                         for (const auto& line :
                              QString::fromUtf8(chunk).split('\n', Qt::SkipEmptyParts))
                         {
                             const auto trimmed = line.trimmed();
                             if (!trimmed.isEmpty())
                                 activity_log.append(instance_id, "process", "warn", trimmed.toStdString());
                         }
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
    const auto art = ensure_pulled(model_id, request->quant(), request->hf_repo(), monitor);
    PullModelReply reply;
    reply.set_model_id(art.id);
    reply.set_path(art.path);
    reply.set_reply_message("downloaded");
    auto* lp = reply.mutable_launch_progress();
    lp->set_percent_complete("100");
    log_lifecycle(art.id, "info", fmt::format("pull complete: {}", art.path));
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

    auto done = std::make_shared<std::promise<void>>();
    QTimer::singleShot(0, process->thread(), [process, done]() {
        stop_process_on_thread(process);
        done->set_value();
    });
    done->get_future().wait();
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
    const auto art = ensure_pulled(model_id, request->quant(), "", monitor);
    const auto ctx = request->ctx_size() > 0 ? request->ctx_size() : 4096;
    const auto claim = estimate_claim(art, ctx);
    const auto kind = select_backend();

    auto result = pool.try_claim(instance_id, WorkloadKind::llm, claim, 0);
    if (!result.accepted)
        throw std::runtime_error(result.message);

    LoadedSession session;
    session.instance_id = instance_id;
    session.model_id = model_id;
    session.openai_id = openai_id_for_instance(model_id, instance_id);
    session.backend = backend_name(kind);
    session.path = art.path;
    session.port = pick_loopback_port();
    session.memory = claim;

    try
    {
        if (kind == BackendKind::mlx)
        {
            auto mlx = llm::locate_binary(nullptr, {"mlx_lm.server"});
            if (mlx.isEmpty())
                mlx = llm::locate_binary(nullptr, {"python3", "python"});
            if (mlx.isEmpty())
                throw std::runtime_error("mlx_lm.server is not on PATH");
            session.process = platform::make_process(
                std::make_unique<MlxServerProcessSpec>(mlx, QString::fromStdString(art.path), session.port));
        }
        else
        {
            const auto llama = llm::locate_binary(mp::llama_server_env_var,
                                                  {"llama-server", "llama_server"});
            if (llama.isEmpty())
                throw std::runtime_error(
                    "llama-server is not installed. Set HYPERPASS_LLAMA_SERVER or add it to PATH.");
            session.process = platform::make_process(std::make_unique<LlamaServerProcessSpec>(
                llama,
                QString::fromStdString(art.path),
                QString::fromStdString(session.openai_id),
                session.port,
                ctx,
                gpu_layers(kind)));
        }
        session.process->start();
        if (!session.process->wait_for_started(10000))
            throw std::runtime_error("inference backend failed to start");
        if (!wait_until_ready(session.port))
            throw std::runtime_error("inference backend started but did not become ready on 127.0.0.1");
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
    if (!result.message.empty())
        reply.set_reply_message(result.message);

    {
        std::lock_guard lock{mutex};
        sessions[instance_id] = std::move(session);
        if (sessions[instance_id].process)
        {
            attach_process_logging(instance_id, sessions[instance_id].process.get());
            QObject::connect(sessions[instance_id].process.get(),
                             &Process::finished,
                             this,
                             [this, instance_id](ProcessState) { unload_instance(instance_id); });
        }
    }
    vault.touch(model_id);
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
    {
        std::lock_guard lock{mutex};
        auto it = sessions.find(instance_id);
        if (it == sessions.end())
        {
            pool.release(instance_id);
            return;
        }
        dying = std::move(it->second.process);
        runner_thread = std::move(it->second.runner_thread);
        sessions.erase(it);
        pool.release(instance_id);
    }
    if (dying)
        stop_process(dying.get());
    if (runner_thread)
    {
        runner_thread->quit();
        runner_thread->wait(5000);
    }
}

void mp::LlmService::unload_all_for_model(const std::string& model_id)
{
    std::vector<std::string> instances;
    {
        std::lock_guard lock{mutex};
        for (const auto& [id, session] : sessions)
        {
            if (session.model_id == model_id)
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
        unload_instance(request->instance_id());
    else if (!request->model_id().empty())
        unload_all_for_model(request->model_id());

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
    for (const auto& [instance_id, session] : sessions)
    {
        auto* info = reply.add_models();
        info->set_instance_id(instance_id);
        info->set_model_id(session.model_id);
        info->set_openai_id(session.openai_id);
        info->set_backend(session.backend);
        info->set_path(session.path);
        info->set_port(static_cast<uint32_t>(session.port));
        info->set_memory_claimed(static_cast<uint64_t>(session.memory.in_bytes()));
        info->set_state(session.process && session.process->running() ? "loaded" : "stopped");
    }
    for (const auto& art : vault.list())
    {
        ModelSuggestion cached;
        cached.set_id(art.id);
        cached.set_name(art.id);
        cached.set_best_quant(art.quant);
        cached.set_hf_repo(art.repo);
        cached.set_filename(art.filename);
        cached.set_memory_required_gb(static_cast<double>(art.size_bytes) / (1024.0 * 1024.0 * 1024.0));
        *reply.add_cached() = cached;
    }
    server->Write(reply);
}

void mp::LlmService::list_llm_backends(
    const ListLlmBackendsRequest*,
    grpc::ServerReaderWriterInterface<ListLlmBackendsReply, ListLlmBackendsRequest>* server)
{
    const auto selected = backend_name(select_backend());
    ListLlmBackendsReply reply;
    reply.set_selected_backend(selected);
    for (const auto& row : llm::probe_backends(selected))
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
    }
    server->Write(reply);
}

void mp::LlmService::create_api_key(
    const CreateApiKeyRequest* request,
    grpc::ServerReaderWriterInterface<CreateApiKeyReply, CreateApiKeyRequest>* server)
{
    const auto created = keys.create(request->label());
    CreateApiKeyReply reply;
    reply.set_id(created.record.id);
    reply.set_prefix(created.record.prefix);
    reply.set_secret(created.secret);
    reply.set_label(created.record.label);
    server->Write(reply);
}

void mp::LlmService::list_api_keys(
    const ListApiKeysRequest*,
    grpc::ServerReaderWriterInterface<ListApiKeysReply, ListApiKeysRequest>* server)
{
    ListApiKeysReply reply;
    for (const auto& key : keys.list())
    {
        auto* info = reply.add_keys();
        info->set_id(key.id);
        info->set_prefix(key.prefix);
        info->set_label(key.label);
        info->set_created_at(key.created_at);
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
            if (!session.process || !session.process->running())
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
}
