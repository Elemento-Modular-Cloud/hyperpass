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

#include "grpc_backend.h"

namespace mp = multipass;

namespace
{
template <typename Request, typename Reply, typename Method>
grpc::Status call_streaming_rpc(Method method,
                                Request request,
                                Reply& reply,
                                std::chrono::seconds deadline)
{
    grpc::ClientContext context;
    context.set_deadline(std::chrono::system_clock::now() + deadline);

    auto stream = method(&context);
    if (!stream)
        return grpc::Status{grpc::StatusCode::UNAVAILABLE, "failed to open gRPC stream"};

    if (!stream->Write(request))
        return grpc::Status{grpc::StatusCode::UNAVAILABLE, "failed to write gRPC request"};

    stream->WritesDone();

    Reply last;
    while (stream->Read(&last))
        reply = last;

    return stream->Finish();
}

template <typename Request, typename Reply, typename Method>
grpc::Status call_streaming_rpc_noreply(Method method,
                                        Request request,
                                        std::chrono::seconds deadline)
{
    Reply discarded;
    return call_streaming_rpc(method, std::move(request), discarded, deadline);
}
} // namespace

mp::api::GrpcBackend::GrpcBackend(std::shared_ptr<grpc::Channel> channel)
    : channel{std::move(channel)}, rpc_stub{Rpc::NewStub(this->channel)}
{
}

bool mp::api::GrpcBackend::ping(std::chrono::seconds deadline)
{
    return daemon_info(deadline).status.ok();
}

mp::api::DaemonInfoResult mp::api::GrpcBackend::daemon_info(std::chrono::seconds deadline)
{
    DaemonInfoResult result;
    DaemonInfoRequest request;
    request.set_verbosity_level(0);

    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->daemon_info(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::ListResult mp::api::GrpcBackend::list_instances(bool request_ipv4,
                                                         std::chrono::seconds deadline)
{
    ListResult result;
    ListRequest request;
    request.set_verbosity_level(0);
    request.set_snapshots(false);
    request.set_request_ipv4(request_ipv4);

    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->list(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::LaunchResult mp::api::GrpcBackend::launch(const LaunchSpec& spec,
                                                   std::chrono::seconds deadline)
{
    LaunchResult result;
    LaunchRequest request;
    request.set_instance_name(spec.instance_name);
    request.set_image(spec.image);
    request.set_num_cores(spec.num_cores);
    request.set_mem_size(spec.mem_size);
    request.set_disk_space(spec.disk_space);
    request.set_cloud_init_user_data(spec.cloud_init_user_data);
    request.set_verbosity_level(0);
    request.set_timeout(static_cast<int32_t>(deadline.count()));

    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->launch(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::GrpcResult mp::api::GrpcBackend::start(const std::string& instance_name,
                                                std::chrono::seconds deadline)
{
    GrpcResult result;
    StartRequest request;
    request.mutable_instance_names()->add_instance_name(instance_name);
    request.set_verbosity_level(0);
    request.set_timeout(static_cast<int32_t>(deadline.count()));

    result.status = call_streaming_rpc_noreply<StartRequest, StartReply>(
        [this](grpc::ClientContext* ctx) { return rpc_stub->start(ctx); },
        request,
        deadline);
    return result;
}

mp::api::GrpcResult mp::api::GrpcBackend::stop(const std::string& instance_name,
                                               std::chrono::seconds deadline)
{
    GrpcResult result;
    StopRequest request;
    request.mutable_instance_names()->add_instance_name(instance_name);
    request.set_verbosity_level(0);

    result.status = call_streaming_rpc_noreply<StopRequest, StopReply>(
        [this](grpc::ClientContext* ctx) { return rpc_stub->stop(ctx); },
        request,
        deadline);
    return result;
}

mp::api::GrpcResult mp::api::GrpcBackend::restart(const std::string& instance_name,
                                                  std::chrono::seconds deadline)
{
    GrpcResult result;
    RestartRequest request;
    request.mutable_instance_names()->add_instance_name(instance_name);
    request.set_verbosity_level(0);
    request.set_timeout(static_cast<int32_t>(deadline.count()));

    result.status = call_streaming_rpc_noreply<RestartRequest, RestartReply>(
        [this](grpc::ClientContext* ctx) { return rpc_stub->restart(ctx); },
        request,
        deadline);
    return result;
}

mp::api::GrpcResult mp::api::GrpcBackend::delete_instance(const std::string& instance_name,
                                                          bool purge,
                                                          std::chrono::seconds deadline)
{
    GrpcResult result;
    DeleteRequest request;
    auto* pair = request.add_instance_snapshot_pairs();
    pair->set_instance_name(instance_name);
    request.set_purge(purge);
    request.set_verbosity_level(0);

    result.status = call_streaming_rpc_noreply<DeleteRequest, DeleteReply>(
        [this](grpc::ClientContext* ctx) { return rpc_stub->delet(ctx); },
        request,
        deadline);
    return result;
}

mp::api::FindResult mp::api::GrpcBackend::find(const std::string& search,
                                               const std::string& remote,
                                               std::chrono::seconds deadline)
{
    FindResult result;
    FindRequest request;
    request.set_search_string(search);
    request.set_remote_name(remote);
    request.set_verbosity_level(0);

    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->find(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::InfoResult mp::api::GrpcBackend::info(const std::string& instance_name,
                                               std::chrono::seconds deadline)
{
    InfoResult result;
    InfoRequest request;
    auto* pair = request.add_instance_snapshot_pairs();
    pair->set_instance_name(instance_name);
    request.set_verbosity_level(0);

    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->info(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::VersionResult mp::api::GrpcBackend::version(std::chrono::seconds deadline)
{
    VersionResult result;
    VersionRequest request;
    request.set_verbosity_level(0);

    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->version(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::FindModelsResult mp::api::GrpcBackend::find_models(int limit,
                                                            const std::string& use_case,
                                                            std::chrono::seconds deadline)
{
    FindModelsResult result;
    FindModelsRequest request;
    request.set_verbosity_level(0);
    request.set_limit(limit);
    request.set_use_case(use_case);
    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->find_models(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::PullModelResult mp::api::GrpcBackend::pull_model(const std::string& model_id,
                                                          const std::string& quant,
                                                          std::chrono::seconds deadline)
{
    PullModelResult result;
    PullModelRequest request;
    request.set_model_id(model_id);
    request.set_quant(quant);
    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->pull_model(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::LoadModelResult mp::api::GrpcBackend::load_model(const std::string& model_id,
                                                          const std::string& quant,
                                                          int ctx_size,
                                                          std::chrono::seconds deadline)
{
    LoadModelResult result;
    LoadModelRequest request;
    request.set_model_id(model_id);
    request.set_quant(quant);
    request.set_ctx_size(ctx_size);
    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->load_model(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::GrpcResult mp::api::GrpcBackend::unload_model(const std::string& model_id,
                                                       std::chrono::seconds deadline)
{
    GrpcResult result;
    UnloadModelRequest request;
    request.set_model_id(model_id);
    result.status = call_streaming_rpc_noreply<UnloadModelRequest, UnloadModelReply>(
        [this](grpc::ClientContext* ctx) { return rpc_stub->unload_model(ctx); },
        request,
        deadline);
    return result;
}

mp::api::ListModelsResult mp::api::GrpcBackend::list_models(std::chrono::seconds deadline)
{
    ListModelsResult result;
    ListModelsRequest request;
    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->list_models(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::CreateApiKeyResult mp::api::GrpcBackend::create_api_key(const std::string& label,
                                                                 std::chrono::seconds deadline)
{
    CreateApiKeyResult result;
    CreateApiKeyRequest request;
    request.set_label(label);
    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->create_api_key(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::ListApiKeysResult mp::api::GrpcBackend::list_api_keys(std::chrono::seconds deadline)
{
    ListApiKeysResult result;
    ListApiKeysRequest request;
    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->list_api_keys(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::GrpcResult mp::api::GrpcBackend::revoke_api_key(const std::string& id,
                                                         std::chrono::seconds deadline)
{
    GrpcResult result;
    RevokeApiKeyRequest request;
    request.set_id(id);
    request.set_prefix(id);
    result.status = call_streaming_rpc_noreply<RevokeApiKeyRequest, RevokeApiKeyReply>(
        [this](grpc::ClientContext* ctx) { return rpc_stub->revoke_api_key(ctx); },
        request,
        deadline);
    return result;
}

mp::api::VerifyApiKeyResult mp::api::GrpcBackend::verify_api_key(const std::string& secret,
                                                                 std::chrono::seconds deadline)
{
    VerifyApiKeyResult result;
    VerifyApiKeyRequest request;
    request.set_secret(secret);
    result.status = call_streaming_rpc(
        [this](grpc::ClientContext* ctx) { return rpc_stub->verify_api_key(ctx); },
        request,
        result.reply,
        deadline);
    return result;
}

mp::api::GrpcResult mp::api::GrpcBackend::touch_model(const std::string& instance_id,
                                                      std::chrono::seconds deadline,
                                                      const std::string& method,
                                                      const std::string& path,
                                                      int status_code)
{
    GrpcResult result;
    TouchModelRequest request;
    request.set_instance_id(instance_id);
    if (!method.empty())
        request.set_method(method);
    if (!path.empty())
        request.set_path(path);
    if (status_code != 0)
        request.set_status_code(status_code);
    result.status = call_streaming_rpc_noreply<TouchModelRequest, TouchModelReply>(
        [this](grpc::ClientContext* ctx) { return rpc_stub->touch_model(ctx); },
        request,
        deadline);
    return result;
}
