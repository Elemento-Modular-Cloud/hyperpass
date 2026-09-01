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
#include "operation_tracker.h"

#include <httplib.h>

#include <boost/json.hpp>

#include <cstdint>
#include <memory>
#include <string>
#include <string_view>

namespace multipass::api
{

void register_health_handlers(httplib::Server& server,
                              GrpcBackend& hyperpass_backend,
                              GrpcBackend* multipass_backend);
void register_instance_handlers(httplib::Server& server,
                                GrpcBackend& hyperpass_backend,
                                GrpcBackend* multipass_backend);
void register_operation_handlers(httplib::Server& server, OperationTracker& tracker);
void register_model_control_handlers(httplib::Server& server, GrpcBackend& hyperpass_backend);
void register_openai_handlers(httplib::Server& server, GrpcBackend& hyperpass_backend);

/** Append instances from a ListReply into a JSON array, tagging each with source. */
void append_instances_from_reply(boost::json::array& out,
                                 const ListReply& reply,
                                 std::string_view source);

/** Map a ListReply to a provisional JSON body with a source tag on each instance. */
std::string list_reply_to_json(const ListReply& reply, std::string_view source);

/** Map an Operation to JSON. */
std::string operation_to_json(const Operation& op);

/** Parse a matcher canallocate body; 0 means "any remaining RAM". */
std::int64_t requested_mib_from_canallocate_body(std::string_view body);

inline bool can_allocate_from_available(std::int64_t available_mib, std::int64_t requested_mib)
{
    return requested_mib <= 0 ? available_mib > 0 : available_mib >= requested_mib;
}

} // namespace multipass::api
