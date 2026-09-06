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

#pragma once

#include "api_key_store.h"
#include "llm_activity_log.h"
#include "llmfit_advisor.h"
#include "model_vault.h"

#include <multipass/path.h>
#include <multipass/process/process.h>
#include <multipass/resource_pool.h>
#include <multipass/rpc/multipass.grpc.pb.h>
#include <multipass/url_downloader.h>

#include <QObject>
#include <QThread>
#include <QTimer>

#include <chrono>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace grpc
{
template <typename W, typename R>
class ServerReaderWriterInterface;
}

namespace multipass
{

struct LoadedSession
{
    std::string instance_id;
    std::string model_id;
    std::string openai_id;
    std::string backend;
    std::string path;
    int port{0};
    qint64 pid{0};
    int ctx_size{4096};
    int max_tokens{0}; // 0 = unlimited
    MemorySize memory;
    std::unique_ptr<Process> process;
    std::unique_ptr<QThread> runner_thread;
    std::chrono::steady_clock::time_point last_used{std::chrono::steady_clock::now()};
};

class LlmService : public QObject
{
    Q_OBJECT
public:
    LlmService(ResourcePool& pool, URLDownloader& downloader, Path data_directory);
    ~LlmService() override;

    void restore_claims();

    void find_models(const FindModelsRequest* request,
                     grpc::ServerReaderWriterInterface<FindModelsReply, FindModelsRequest>* server);
    void pull_model(const PullModelRequest* request,
                    grpc::ServerReaderWriterInterface<PullModelReply, PullModelRequest>* server);
    void load_model(const LoadModelRequest* request,
                    grpc::ServerReaderWriterInterface<LoadModelReply, LoadModelRequest>* server);
    void load_model_impl(const LoadModelRequest* request,
                         grpc::ServerReaderWriterInterface<LoadModelReply, LoadModelRequest>* server,
                         std::unique_ptr<QThread>& runner_thread,
                         bool& runner_transferred);
    void unload_model(
        const UnloadModelRequest* request,
        grpc::ServerReaderWriterInterface<UnloadModelReply, UnloadModelRequest>* server);
    void list_models(const ListModelsRequest* request,
                     grpc::ServerReaderWriterInterface<ListModelsReply, ListModelsRequest>* server);
    void list_llm_backends(
        const ListLlmBackendsRequest* request,
        grpc::ServerReaderWriterInterface<ListLlmBackendsReply, ListLlmBackendsRequest>* server);
    void install_llm_backend(
        const InstallLlmBackendRequest* request,
        grpc::ServerReaderWriterInterface<InstallLlmBackendReply, InstallLlmBackendRequest>* server);
    void create_api_key(
        const CreateApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<CreateApiKeyReply, CreateApiKeyRequest>* server);
    void list_api_keys(
        const ListApiKeysRequest* request,
        grpc::ServerReaderWriterInterface<ListApiKeysReply, ListApiKeysRequest>* server);
    void update_api_key(
        const UpdateApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<UpdateApiKeyReply, UpdateApiKeyRequest>* server);
    void revoke_api_key(
        const RevokeApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<RevokeApiKeyReply, RevokeApiKeyRequest>* server);
    void verify_api_key(
        const VerifyApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<VerifyApiKeyReply, VerifyApiKeyRequest>* server);
    void touch_model(const TouchModelRequest* request,
                     grpc::ServerReaderWriterInterface<TouchModelReply, TouchModelRequest>* server);
    void delete_model(
        const DeleteModelRequest* request,
        grpc::ServerReaderWriterInterface<DeleteModelReply, DeleteModelRequest>* server);
    void stream_model_logs(
        const StreamModelLogsRequest* request,
        grpc::ServerReaderWriterInterface<StreamModelLogsReply, StreamModelLogsRequest>* server);

    void unload_instance(const std::string& instance_id);
    void unload_all_for_model(const std::string& model_id);
    std::optional<LoadedSession*> session_by_openai_id(const std::string& openai_id);
    bool is_loaded(const std::string& model_id) const;

private:
    enum class BackendKind
    {
        llamacpp_cpu,
        llamacpp_metal,
        llamacpp_cuda,
        mlx
    };

    BackendKind select_backend() const;
    BackendKind resolve_backend(const LoadModelRequest* request) const;
    std::string backend_name(BackendKind kind) const;
    int gpu_layers(BackendKind kind) const;
    MemorySize estimate_claim(const ModelArtifact& artifact, int ctx_size) const;
    int pick_loopback_port() const;
    bool wait_until_ready(int port) const;
    ModelArtifact ensure_pulled(const std::string& model_id,
                                const std::string& quant,
                                const std::string& hf_repo,
                                const ProgressMonitor& monitor);
    ResolvedGguf resolve_or_throw(const std::string& model_id,
                                  const std::string& quant,
                                  const std::string& hf_repo = {});
    std::string hf_token() const;
    std::chrono::seconds idle_ttl() const;
    void persist_sessions() const;
    QString sessions_file() const;
    bool session_is_live(const LoadedSession& session) const;
    void restore_session(LoadedSession session);
    void reap_dead_sessions();
    void idle_unload_tick();
    std::string openai_id_for_instance(const std::string& model_id,
                                       const std::string& instance_id) const;
    void attach_process_logging(const std::string& instance_id, Process* process);
    void log_lifecycle(const std::string& instance_id,
                       const std::string& level,
                       const std::string& message);
    static void stop_process(Process* process);
    static void stop_process_on_thread(Process* process);

    ResourcePool& pool;
    ModelVault vault;
    LlmfitAdvisor advisor;
    ApiKeyStore keys;
    LlmActivityLog activity_log;
    URLDownloader& downloader;
    Path data_directory;
    std::unordered_map<std::string, LoadedSession> sessions;
    mutable std::mutex mutex;
    QTimer idle_timer;
};

} // namespace multipass
