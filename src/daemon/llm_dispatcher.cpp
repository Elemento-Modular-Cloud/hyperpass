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

#include "llm_dispatcher.h"

#include "daemon_rpc.h"
#include "llm_service.h"

#include <multipass/daemon_rpc_context.h>

#include <QMetaObject>
#include <QThread>

#include <grpcpp/grpcpp.h>

namespace mp = multipass;

grpc::Status mp::LlmDispatcher::status_for_exception(const std::exception& e)
{
    const std::string msg{e.what()};
    const auto code = msg.find("Not enough host memory") != std::string::npos
                          ? grpc::StatusCode::RESOURCE_EXHAUSTED
                          : grpc::StatusCode::FAILED_PRECONDITION;
    return grpc::Status{code, msg, ""};
}

mp::LlmDispatcher::LlmDispatcher(ResourcePool& pool, URLDownloader& downloader, Path data_directory)
    : llm_service{std::make_unique<LlmService>(pool, downloader, data_directory)}
{
    worker_pool_.setMaxThreadCount(4);
}

mp::LlmDispatcher::~LlmDispatcher()
{
    try
    {
        shutdown();
    }
    catch (...)
    {
    }
    worker_pool_.waitForDone();
}

void mp::LlmDispatcher::shutdown()
{
    worker_pool_.waitForDone();
    llm_service.reset();
}

void mp::LlmDispatcher::unload_instances_blocking(const std::vector<std::string>& instance_ids)
{
    if (instance_ids.empty())
        return;

    if (QThread::currentThread() == thread())
    {
        for (const auto& id : instance_ids)
            llm_service->unload_instance(id);
        return;
    }

    QMetaObject::invokeMethod(
        this,
        [this, instance_ids] {
            for (const auto& id : instance_ids)
                llm_service->unload_instance(id);
        },
        Qt::BlockingQueuedConnection);
}

template <typename Work>
void mp::LlmDispatcher::run_sync(DaemonRpcContext* context, Work&& work)
{
    try
    {
        work();
        context->set_value(grpc::Status::OK);
    }
    catch (const std::exception& e)
    {
        context->set_value(status_for_exception(e));
    }
}

template <typename Work>
void mp::LlmDispatcher::run_async(DaemonRpcContext* context, Work&& work)
{
    worker_pool_.start([context, work = std::forward<Work>(work)]() mutable {
        try
        {
            work();
            context->set_value(grpc::Status::OK);
        }
        catch (const std::exception& e)
        {
            context->set_value(status_for_exception(e));
        }
    });
}

void mp::LlmDispatcher::find_models(
    const FindModelsRequest* request,
    grpc::ServerReaderWriterInterface<FindModelsReply, FindModelsRequest>* server,
    DaemonRpcContext* context)
{
    run_async(context, [this, request, server] { llm_service->find_models(request, server); });
}

void mp::LlmDispatcher::pull_model(
    const PullModelRequest* request,
    grpc::ServerReaderWriterInterface<PullModelReply, PullModelRequest>* server,
    DaemonRpcContext* context)
{
    run_async(context, [this, request, server] { llm_service->pull_model(request, server); });
}

void mp::LlmDispatcher::load_model(
    const LoadModelRequest* request,
    grpc::ServerReaderWriterInterface<LoadModelReply, LoadModelRequest>* server,
    DaemonRpcContext* context)
{
    run_async(context, [this, request, server] { llm_service->load_model(request, server); });
}

void mp::LlmDispatcher::unload_model(
    const UnloadModelRequest* request,
    grpc::ServerReaderWriterInterface<UnloadModelReply, UnloadModelRequest>* server,
    DaemonRpcContext* context)
{
    run_async(context, [this, request, server] { llm_service->unload_model(request, server); });
}

void mp::LlmDispatcher::list_models(
    const ListModelsRequest* request,
    grpc::ServerReaderWriterInterface<ListModelsReply, ListModelsRequest>* server,
    DaemonRpcContext* context)
{
    run_sync(context, [this, request, server] { llm_service->list_models(request, server); });
}

void mp::LlmDispatcher::list_llm_backends(
    const ListLlmBackendsRequest* request,
    grpc::ServerReaderWriterInterface<ListLlmBackendsReply, ListLlmBackendsRequest>* server,
    DaemonRpcContext* context)
{
    run_async(context, [this, request, server] { llm_service->list_llm_backends(request, server); });
}

void mp::LlmDispatcher::install_llm_backend(
    const InstallLlmBackendRequest* request,
    grpc::ServerReaderWriterInterface<InstallLlmBackendReply, InstallLlmBackendRequest>* server,
    DaemonRpcContext* context)
{
    run_async(context, [this, request, server] { llm_service->install_llm_backend(request, server); });
}

void mp::LlmDispatcher::create_api_key(
    const CreateApiKeyRequest* request,
    grpc::ServerReaderWriterInterface<CreateApiKeyReply, CreateApiKeyRequest>* server,
    DaemonRpcContext* context)
{
    run_async(context, [this, request, server] { llm_service->create_api_key(request, server); });
}

void mp::LlmDispatcher::list_api_keys(
    const ListApiKeysRequest* request,
    grpc::ServerReaderWriterInterface<ListApiKeysReply, ListApiKeysRequest>* server,
    DaemonRpcContext* context)
{
    run_sync(context, [this, request, server] { llm_service->list_api_keys(request, server); });
}

void mp::LlmDispatcher::revoke_api_key(
    const RevokeApiKeyRequest* request,
    grpc::ServerReaderWriterInterface<RevokeApiKeyReply, RevokeApiKeyRequest>* server,
    DaemonRpcContext* context)
{
    run_async(context, [this, request, server] { llm_service->revoke_api_key(request, server); });
}

void mp::LlmDispatcher::verify_api_key(
    const VerifyApiKeyRequest* request,
    grpc::ServerReaderWriterInterface<VerifyApiKeyReply, VerifyApiKeyRequest>* server,
    DaemonRpcContext* context)
{
    run_sync(context, [this, request, server] { llm_service->verify_api_key(request, server); });
}

void mp::LlmDispatcher::touch_model(
    const TouchModelRequest* request,
    grpc::ServerReaderWriterInterface<TouchModelReply, TouchModelRequest>* server,
    DaemonRpcContext* context)
{
    run_sync(context, [this, request, server] { llm_service->touch_model(request, server); });
}

void mp::LlmDispatcher::delete_model(
    const DeleteModelRequest* request,
    grpc::ServerReaderWriterInterface<DeleteModelReply, DeleteModelRequest>* server,
    DaemonRpcContext* context)
{
    run_async(context, [this, request, server] { llm_service->delete_model(request, server); });
}

void mp::LlmDispatcher::stream_model_logs(
    const StreamModelLogsRequest* request,
    grpc::ServerReaderWriterInterface<StreamModelLogsReply, StreamModelLogsRequest>* server,
    DaemonRpcContext* context)
{
    run_async(context, [this, request, server] { llm_service->stream_model_logs(request, server); });
}
