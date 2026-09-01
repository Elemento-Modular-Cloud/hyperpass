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
#include "llmfit_advisor.h"
#include "model_vault.h"

#include <multipass/path.h>
#include <multipass/process/process.h>
#include <multipass/resource_pool.h>
#include <multipass/rpc/multipass.grpc.pb.h>
#include <multipass/url_downloader.h>

#include <QObject>
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
    std::string model_id;
    std::string openai_id;
    std::string backend;
    std::string path;
    int port{0};
    MemorySize memory;
    std::unique_ptr<Process> process;
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
    void unload_model(
        const UnloadModelRequest* request,
        grpc::ServerReaderWriterInterface<UnloadModelReply, UnloadModelRequest>* server);
    void list_models(const ListModelsRequest* request,
                     grpc::ServerReaderWriterInterface<ListModelsReply, ListModelsRequest>* server);
    void create_api_key(
        const CreateApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<CreateApiKeyReply, CreateApiKeyRequest>* server);
    void list_api_keys(
        const ListApiKeysRequest* request,
        grpc::ServerReaderWriterInterface<ListApiKeysReply, ListApiKeysRequest>* server);
    void revoke_api_key(
        const RevokeApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<RevokeApiKeyReply, RevokeApiKeyRequest>* server);
    void verify_api_key(
        const VerifyApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<VerifyApiKeyReply, VerifyApiKeyRequest>* server);
    void touch_model(const TouchModelRequest* request,
                     grpc::ServerReaderWriterInterface<TouchModelReply, TouchModelRequest>* server);

    void unload_named(const std::string& model_id);
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
    std::string backend_name(BackendKind kind) const;
    int gpu_layers(BackendKind kind) const;
    MemorySize estimate_claim(const ModelArtifact& artifact, int ctx_size) const;
    int pick_loopback_port() const;
    bool wait_until_ready(int port) const;
    ModelArtifact ensure_pulled(const std::string& model_id,
                                const std::string& quant,
                                const ProgressMonitor& monitor);
    ResolvedGguf resolve_or_throw(const std::string& model_id, const std::string& quant);
    std::string hf_token() const;
    std::chrono::seconds idle_ttl() const;
    void persist_sessions() const;
    void reap_dead_sessions();
    void idle_unload_tick();
    std::string openai_id_for(const std::string& model_id) const;

    ResourcePool& pool;
    ModelVault vault;
    LlmfitAdvisor advisor;
    ApiKeyStore keys;
    Path data_directory;
    std::unordered_map<std::string, LoadedSession> sessions;
    mutable std::mutex mutex;
    QTimer idle_timer;
};

} // namespace multipass
