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

#include "config.h"
#include "grpc_backend.h"
#include "operation_tracker.h"
#include "vm_registry.h"

#ifndef CPPHTTPLIB_OPENSSL_SUPPORT
#define CPPHTTPLIB_OPENSSL_SUPPORT
#endif
#include <httplib.h>

#include <atomic>
#include <memory>
#include <thread>
#include <vector>

namespace multipass::api
{

class ApiServer
{
public:
    ApiServer(ApiConfig config,
              std::shared_ptr<GrpcBackend> elp_backend,
              std::shared_ptr<VmRegistry> registry,
              std::shared_ptr<GrpcBackend> multipass_backend = nullptr);
    ~ApiServer();

    /** Blocking listen. Returns false if bind/listen failed on every host. */
    bool listen();

    void stop();

    OperationTracker& operations()
    {
        return tracker;
    }

    VmRegistry& registry()
    {
        return *vm_registry;
    }

private:
    std::unique_ptr<httplib::Server> make_one_server();
    void register_routes(httplib::Server& server);
    void retry_bind_until_stopped(size_t server_index, std::string host, int port);

    ApiConfig config;
    std::shared_ptr<GrpcBackend> elp_backend;
    std::shared_ptr<VmRegistry> vm_registry;
    std::shared_ptr<GrpcBackend> multipass_backend;
    OperationTracker tracker;
    std::vector<std::unique_ptr<httplib::Server>> servers;
    std::vector<std::thread> listen_threads;
    std::atomic<bool> stopping{false};
};

} // namespace multipass::api
