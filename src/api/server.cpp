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
#include "tls_fingerprint.h"

#include <multipass/format.h>
#include <multipass/logging/log.h>

#include <boost/json.hpp>

#include <stdexcept>

namespace mp = multipass;
namespace mpl = multipass::logging;
namespace json = boost::json;

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
    make_server();
    register_routes();
}

void mp::api::ApiServer::make_server()
{
    if (config.use_https)
    {
#ifdef CPPHTTPLIB_OPENSSL_SUPPORT
        httplib::SSLServer::PemMemory pem{};
        pem.cert_pem = config.cert_pem.c_str();
        pem.cert_pem_len = config.cert_pem.size();
        pem.key_pem = config.key_pem.c_str();
        pem.key_pem_len = config.key_pem.size();
        pem.client_ca_pem = nullptr;
        pem.client_ca_pem_len = 0;
        pem.private_key_password = nullptr;

        auto ssl_server = std::make_unique<httplib::SSLServer>(pem);
        if (!ssl_server->is_valid())
        {
            throw std::runtime_error(
                fmt::format("failed to initialize HTTPS server (ssl error {})",
                            ssl_server->ssl_last_error()));
        }
        server = std::move(ssl_server);
#else
        throw std::runtime_error("HTTPS requested but OpenSSL support is unavailable");
#endif
    }
    else
    {
        server = std::make_unique<httplib::Server>();
    }
}

void mp::api::ApiServer::register_routes()
{
    server->set_logger([](const httplib::Request& req, const httplib::Response& res) {
        mpl::log(mpl::Level::info,
                 category,
                 "{} {} -> {} ({} bytes, from {})",
                 req.method,
                 req.path,
                 res.status,
                 res.body.size(),
                 req.remote_addr);
    });

    server->set_pre_routing_handler(
        [this](const httplib::Request& req, httplib::Response& res) -> httplib::Server::HandlerResponse {
            mpl::log(mpl::Level::debug,
                     category,
                     "request {} {} ({} bytes, from {})",
                     req.method,
                     req.path,
                     req.body.size(),
                     req.remote_addr);

            if (is_public_path(req.path))
                return httplib::Server::HandlerResponse::Unhandled;

            const auto auth = check_bearer_auth(req.get_header_value("Authorization"), config);
            if (auth != AuthResult::ok)
            {
                mpl::log(mpl::Level::warning,
                         category,
                         "auth failed for {} {} ({})",
                         req.method,
                         req.path,
                         auth == AuthResult::missing ? "missing_token" : "invalid_token");
                res.status = 401;
                res.set_header("WWW-Authenticate", "Bearer");
                res.set_content(auth_error_body(auth), "application/json");
                return httplib::Server::HandlerResponse::Handled;
            }

            return httplib::Server::HandlerResponse::Unhandled;
        });

    auto fingerprint_handler = [this](const httplib::Request&, httplib::Response& res) {
        json::object body;
        if (!config.use_https || config.tls_fingerprint.empty())
        {
            body["error"] = "https_disabled";
            body["message"] = "TLS fingerprint available only when serving HTTPS (default; disabled via --http)";
            res.status = 503;
            res.set_content(json::serialize(body), "application/json");
            return;
        }
        body["fingerprint"] = config.tls_fingerprint;
        body["validated"] = false;
        res.status = 200;
        res.set_content(json::serialize(body), "application/json");
    };

    // Electros-compatible: dial host:7777 (fallback :7772) TLS and return peer fingerprint.
    // Same listen port as the VM API; real AtomOS matcher has no such HTTP route — Electros
    // normally does this on local :47777. Hosted here so everything stays on 7777.
    server->Get("/api/v1/authenticate/cert", [](const httplib::Request& req, httplib::Response& res) {
        const auto host = req.get_param_value("host");
        json::object body;
        if (host.empty())
        {
            // FastAPI-ish missing field shape Electros clients already tolerate as 4xx.
            body["error"] = "Bad Request";
            body["description"] = "Query parameter 'host' is required";
            res.status = 400;
            res.set_content(json::serialize(body), "application/json");
            return;
        }

        try
        {
            const auto info = fetch_remote_tls_cert_atomos(host);
            body["fingerprint"] = info.fingerprint;
            body["validated"] = info.validated;
            res.status = 200;
            res.set_content(json::serialize(body), "application/json");
        }
        catch (const std::exception& e)
        {
            mpl::log(mpl::Level::warning,
                     category,
                     "remote cert fetch failed for host={}: {}",
                     host,
                     e.what());
            body["error"] = "Internal Server Error";
            // Match Electros wording (including historical typo) for client compatibility.
            body["description"] = "Something went wrong while retrieveing remote server certificate";
            res.status = 500;
            res.set_content(json::serialize(body), "application/json");
        }
    });
    server->Get("/fingerprint", fingerprint_handler);

    register_service_handlers(*server, *hyperpass_backend, *vm_registry);
    register_health_handlers(*server, *hyperpass_backend, multipass_backend.get());
    register_instance_handlers(*server, *hyperpass_backend, multipass_backend.get());
    register_operation_handlers(*server, tracker);
}

bool mp::api::ApiServer::listen()
{
    std::string host;
    int port = 0;
    parse_listen_address(config.listen_address, host, port);

    const auto scheme = config.use_https ? "https" : "http";
    mpl::log(mpl::Level::info,
             category,
             "listening on {}://{}:{} (hyperpass={}, multipass={}, verbosity={})",
             scheme,
             host,
             port,
             config.daemon_address,
             multipass_backend ? "enabled" : "disabled",
             mpl::as_string(config.verbosity_level));

    if (config.use_https)
    {
        mpl::log(mpl::Level::info,
                 category,
                 "TLS fingerprint (AtomOS verify/trust): {}",
                 config.tls_fingerprint);
    }

    return server->listen(host, port);
}

void mp::api::ApiServer::stop()
{
    if (server)
        server->stop();
}
