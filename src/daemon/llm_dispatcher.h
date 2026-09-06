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

#include <multipass/path.h>
#include <multipass/resource_pool.h>
#include <multipass/rpc/multipass.grpc.pb.h>
#include <multipass/url_downloader.h>

#include <QObject>
#include <QThreadPool>

#include <memory>
#include <string>
#include <vector>

namespace grpc
{
template <typename W, typename R>
class ServerReaderWriterInterface;
}

namespace multipass
{
struct DaemonRpcContext;
class LlmService;

class LlmDispatcher : public QObject
{
    Q_OBJECT
public:
    LlmDispatcher(ResourcePool& pool, URLDownloader& downloader, Path data_directory);
    ~LlmDispatcher() override;

    void unload_instances_blocking(const std::vector<std::string>& instance_ids);

public slots:
    void shutdown();

    void find_models(const FindModelsRequest* request,
                     grpc::ServerReaderWriterInterface<FindModelsReply, FindModelsRequest>* server,
                     DaemonRpcContext* context);
    void pull_model(const PullModelRequest* request,
                    grpc::ServerReaderWriterInterface<PullModelReply, PullModelRequest>* server,
                    DaemonRpcContext* context);
    void load_model(const LoadModelRequest* request,
                    grpc::ServerReaderWriterInterface<LoadModelReply, LoadModelRequest>* server,
                    DaemonRpcContext* context);
    void unload_model(
        const UnloadModelRequest* request,
        grpc::ServerReaderWriterInterface<UnloadModelReply, UnloadModelRequest>* server,
        DaemonRpcContext* context);
    void list_models(
        const ListModelsRequest* request,
        grpc::ServerReaderWriterInterface<ListModelsReply, ListModelsRequest>* server,
        DaemonRpcContext* context);
    void list_llm_backends(
        const ListLlmBackendsRequest* request,
        grpc::ServerReaderWriterInterface<ListLlmBackendsReply, ListLlmBackendsRequest>* server,
        DaemonRpcContext* context);
    void install_llm_backend(
        const InstallLlmBackendRequest* request,
        grpc::ServerReaderWriterInterface<InstallLlmBackendReply, InstallLlmBackendRequest>* server,
        DaemonRpcContext* context);
    void create_api_key(
        const CreateApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<CreateApiKeyReply, CreateApiKeyRequest>* server,
        DaemonRpcContext* context);
    void list_api_keys(
        const ListApiKeysRequest* request,
        grpc::ServerReaderWriterInterface<ListApiKeysReply, ListApiKeysRequest>* server,
        DaemonRpcContext* context);
    void update_api_key(
        const UpdateApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<UpdateApiKeyReply, UpdateApiKeyRequest>* server,
        DaemonRpcContext* context);
    void revoke_api_key(
        const RevokeApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<RevokeApiKeyReply, RevokeApiKeyRequest>* server,
        DaemonRpcContext* context);
    void verify_api_key(
        const VerifyApiKeyRequest* request,
        grpc::ServerReaderWriterInterface<VerifyApiKeyReply, VerifyApiKeyRequest>* server,
        DaemonRpcContext* context);
    void touch_model(const TouchModelRequest* request,
                     grpc::ServerReaderWriterInterface<TouchModelReply, TouchModelRequest>* server,
                     DaemonRpcContext* context);
    void delete_model(
        const DeleteModelRequest* request,
        grpc::ServerReaderWriterInterface<DeleteModelReply, DeleteModelRequest>* server,
        DaemonRpcContext* context);
    void stream_model_logs(
        const StreamModelLogsRequest* request,
        grpc::ServerReaderWriterInterface<StreamModelLogsReply, StreamModelLogsRequest>* server,
        DaemonRpcContext* context);

private:
    template <typename Work>
    void run_sync(DaemonRpcContext* context, Work&& work);

    template <typename Work>
    void run_async(DaemonRpcContext* context, Work&& work);

    static grpc::Status status_for_exception(const std::exception& e);

    std::unique_ptr<LlmService> llm_service;
    QThreadPool worker_pool_;
};

} // namespace multipass
