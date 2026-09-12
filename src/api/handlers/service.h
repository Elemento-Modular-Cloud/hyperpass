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

#include "grpc_backend.h"
#include "vm_registry.h"

#include <httplib.h>

#include <string_view>

namespace multipass::api
{

/** Spot v2 VM + marketplace service API (matcher port 7777). */
void register_service_handlers(httplib::Server& server,
                               GrpcBackend& elp_backend,
                               VmRegistry& registry,
                               std::string_view gateway_ca_pem = {},
                               GrpcBackend* multipass_backend = nullptr);

} // namespace multipass::api
