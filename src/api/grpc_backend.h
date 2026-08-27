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

#include <multipass/rpc/multipass.grpc.pb.h>

#include <grpcpp/grpcpp.h>

#include <chrono>
#include <memory>
#include <string>
#include <utility>

namespace multipass::api
{

struct GrpcResult
{
    grpc::Status status;
};

struct DaemonInfoResult : GrpcResult
{
    DaemonInfoReply reply;
};

struct ListResult : GrpcResult
{
    ListReply reply;
};

/**
 * Thin gRPC client over hyperpassd. Uses the same mTLS channel path as the CLI.
 * Streaming RPCs are collapsed to a final reply for unary-style REST handlers.
 */
class GrpcBackend
{
public:
    GrpcBackend(std::shared_ptr<grpc::Channel> channel);

    bool ping(std::chrono::seconds deadline = std::chrono::seconds{5});
    DaemonInfoResult daemon_info(std::chrono::seconds deadline = std::chrono::seconds{30});
    ListResult list_instances(bool request_ipv4 = false,
                              std::chrono::seconds deadline = std::chrono::seconds{30});

    Rpc::StubInterface& stub()
    {
        return *rpc_stub;
    }

private:
    std::shared_ptr<grpc::Channel> channel;
    std::unique_ptr<Rpc::Stub> rpc_stub;
};

} // namespace multipass::api
