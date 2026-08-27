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
