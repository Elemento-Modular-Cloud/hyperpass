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
#include <QTimer>
#include <QUrl>

#include <algorithm>
#include <cctype>
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
    std::lock_guard lock{mutex};
    for (auto& [name, session] : sessions)
    {
        if (session.process)
        {
            session.process->kill();
            session.process->wait_for_finished(3000);
        }
        pool.release(name);
    }
    sessions.clear();
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

std::string mp::LlmService::openai_id_for(const std::string& model_id) const
{
    auto id = slug(model_id);
    if (id.rfind("llama", 0) != 0 && id.find("gpt") == std::string::npos)
        return id;
    return id;
}

mp::ResolvedGguf mp::LlmService::resolve_or_throw(const std::string& model_id,
                                                  const std::string& quant)
{
    if (auto resolved = advisor.resolve(model_id, quant))
        return *resolved;

    throw std::runtime_error(fmt::format(
        "could not resolve a GGUF file for '{}'. llmfit suggestions are often MLX or base "
        "checkpoints; Hyperpass downloads a matching GGUF via `llmfit download --list`. "
        "Try a GGUF repo id such as bartowski/Qwen2.5-Coder-7B-Instruct-GGUF",
        model_id));
}

mp::ModelArtifact mp::LlmService::ensure_pulled(const std::string& model_id,
                                                const std::string& quant,
                                                const ProgressMonitor& monitor)
{
    if (auto existing = vault.find(model_id))
        return *existing;

    const auto resolved = resolve_or_throw(model_id, quant);
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
        if (runtime.empty())
        {
            runtime = select_backend() == BackendKind::mlx ? "mlx" : "llamacpp";
        }
#ifdef Q_OS_MACOS
        const bool unified = true;
#else
        const bool unified = false;
#endif
        const auto models = advisor.recommend(pool.memory_available(),
                                              pool.host_cpus(),
                                              runtime,
                                              request->use_case(),
                                              request->min_fit(),
                                              request->limit(),
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

void mp::LlmService::pull_model(
    const PullModelRequest* request,
    grpc::ServerReaderWriterInterface<PullModelReply, PullModelRequest>* server)
{
    auto monitor = [server](int, int percent) {
        PullModelReply progress;
        auto* lp = progress.mutable_launch_progress();
        lp->set_type(LaunchProgress::IMAGE);
        lp->set_percent_complete(std::to_string(percent));
        server->Write(progress);
        return true;
    };
    const auto art = ensure_pulled(request->model_id(), request->quant(), monitor);
    PullModelReply reply;
    reply.set_model_id(art.id);
    reply.set_path(art.path);
    reply.set_reply_message("downloaded");
    auto* lp = reply.mutable_launch_progress();
    lp->set_percent_complete("100");
    server->Write(reply);
}

void mp::LlmService::load_model(
    const LoadModelRequest* request,
    grpc::ServerReaderWriterInterface<LoadModelReply, LoadModelRequest>* server)
{
    const auto model_id = request->model_id();
    {
        std::lock_guard lock{mutex};
        if (auto it = sessions.find(model_id); it != sessions.end() && it->second.process &&
                                               it->second.process->running())
        {
            LoadModelReply reply;
            reply.set_model_id(model_id);
            reply.set_openai_id(it->second.openai_id);
            reply.set_port(static_cast<uint32_t>(it->second.port));
            reply.set_memory_claimed(static_cast<uint64_t>(it->second.memory.in_bytes()));
            server->Write(reply);
            return;
        }
    }

    auto monitor = [server](int, int percent) {
        LoadModelReply progress;
        auto* lp = progress.mutable_launch_progress();
        lp->set_percent_complete(std::to_string(percent));
        server->Write(progress);
        return true;
    };
    const auto art = ensure_pulled(model_id, request->quant(), monitor);
    const auto ctx = request->ctx_size() > 0 ? request->ctx_size() : 4096;
    const auto claim = estimate_claim(art, ctx);
    const auto kind = select_backend();

    auto result = pool.try_claim(model_id, WorkloadKind::llm, claim, 0);
    if (!result.accepted)
        throw std::runtime_error(result.message);

    LoadedSession session;
    session.model_id = model_id;
    session.openai_id = openai_id_for(model_id);
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
    catch (...)
    {
        pool.release(model_id);
        throw;
    }

    LoadModelReply reply;
    reply.set_model_id(model_id);
    reply.set_openai_id(session.openai_id);
    reply.set_port(static_cast<uint32_t>(session.port));
    reply.set_memory_claimed(static_cast<uint64_t>(session.memory.in_bytes()));
    if (!result.message.empty())
        reply.set_reply_message(result.message);

    {
        std::lock_guard lock{mutex};
        sessions[model_id] = std::move(session);
        if (sessions[model_id].process)
        {
            QObject::connect(sessions[model_id].process.get(),
                             &Process::finished,
                             this,
                             [this, model_id](ProcessState) { unload_named(model_id); });
        }
    }
    vault.touch(model_id);
    server->Write(reply);
}

void mp::LlmService::unload_named(const std::string& model_id)
{
    std::unique_ptr<Process> dying;
    {
        std::lock_guard lock{mutex};
        auto it = sessions.find(model_id);
        if (it == sessions.end())
        {
            pool.release(model_id);
            return;
        }
        dying = std::move(it->second.process);
        sessions.erase(it);
        pool.release(model_id);
    }
    if (dying)
    {
        dying->terminate();
        if (!dying->wait_for_finished(3000))
            dying->kill();
    }
}

void mp::LlmService::unload_model(
    const UnloadModelRequest* request,
    grpc::ServerReaderWriterInterface<UnloadModelReply, UnloadModelRequest>* server)
{
    unload_named(request->model_id());
    UnloadModelReply reply;
    reply.set_model_id(request->model_id());
    server->Write(reply);
}

void mp::LlmService::list_models(
    const ListModelsRequest*,
    grpc::ServerReaderWriterInterface<ListModelsReply, ListModelsRequest>* server)
{
    reap_dead_sessions();
    ListModelsReply reply;
    std::lock_guard lock{mutex};
    for (const auto& [id, session] : sessions)
    {
        auto* info = reply.add_models();
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
    std::lock_guard lock{mutex};
    auto it = sessions.find(request->model_id());
    if (it == sessions.end())
    {
        for (auto& [_, session] : sessions)
        {
            if (session.openai_id == request->model_id())
            {
                session.last_used = std::chrono::steady_clock::now();
                break;
            }
        }
    }
    else
        it->second.last_used = std::chrono::steady_clock::now();
    TouchModelReply reply;
    server->Write(reply);
}

bool mp::LlmService::is_loaded(const std::string& model_id) const
{
    std::lock_guard lock{mutex};
    return sessions.contains(model_id);
}

std::optional<mp::LoadedSession*> mp::LlmService::session_by_openai_id(const std::string& openai_id)
{
    auto it = sessions.find(openai_id);
    if (it != sessions.end())
        return &it->second;
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
        unload_named(id);
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
        unload_named(id);
    }
}

void mp::LlmService::persist_sessions() const
{
}
