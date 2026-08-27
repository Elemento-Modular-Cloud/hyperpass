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

#include <httplib.h>

#include <memory>

namespace multipass::api
{

class ApiServer
{
public:
    ApiServer(ApiConfig config,
              std::shared_ptr<GrpcBackend> hyperpass_backend,
              std::shared_ptr<VmRegistry> registry,
              std::shared_ptr<GrpcBackend> multipass_backend = nullptr);

    /** Blocking listen. Returns false if bind/listen failed. */
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
    void register_routes();

    ApiConfig config;
    std::shared_ptr<GrpcBackend> hyperpass_backend;
    std::shared_ptr<VmRegistry> vm_registry;
    std::shared_ptr<GrpcBackend> multipass_backend;
    OperationTracker tracker;
    httplib::Server server;
};

} // namespace multipass::api
