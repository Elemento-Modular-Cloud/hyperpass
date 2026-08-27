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

#include "server.h"

#include "auth_middleware.h"
#include "handlers/handlers.h"
#include "handlers/service.h"

#include <multipass/format.h>
#include <multipass/logging/log.h>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "api-server";
}

mp::api::ApiServer::ApiServer(ApiConfig config,
                              std::shared_ptr<GrpcBackend> hyperpass_backend,
                              std::shared_ptr<VmRegistry> registry,
                              std::shared_ptr<GrpcBackend> multipass_backend)
    : config{std::move(config)},
      hyperpass_backend{std::move(hyperpass_backend)},
      vm_registry{std::move(registry)},
      multipass_backend{std::move(multipass_backend)}
{
    register_routes();
}

void mp::api::ApiServer::register_routes()
{
    server.set_pre_routing_handler(
        [this](const httplib::Request& req, httplib::Response& res) -> httplib::Server::HandlerResponse {
            if (is_public_path(req.path))
                return httplib::Server::HandlerResponse::Unhandled;

            const auto auth = check_bearer_auth(req.get_header_value("Authorization"), config);
            if (auth != AuthResult::ok)
            {
                res.status = 401;
                res.set_header("WWW-Authenticate", "Bearer");
                res.set_content(auth_error_body(auth), "application/json");
                return httplib::Server::HandlerResponse::Handled;
            }

            return httplib::Server::HandlerResponse::Unhandled;
        });

    register_service_handlers(server, *hyperpass_backend, *vm_registry);
    register_health_handlers(server, *hyperpass_backend, multipass_backend.get());
    register_instance_handlers(server, *hyperpass_backend, multipass_backend.get());
    register_operation_handlers(server, tracker);
}

bool mp::api::ApiServer::listen()
{
    std::string host;
    int port = 0;
    parse_listen_address(config.listen_address, host, port);

    mpl::log_message(
        mpl::Level::info,
        category,
        fmt::format("listening on http://{}:{} (hyperpass={}, multipass={})",
                    host,
                    port,
                    config.daemon_address,
                    multipass_backend ? "enabled" : "disabled"));

    return server.listen(host, port);
}

void mp::api::ApiServer::stop()
{
    server.stop();
}
