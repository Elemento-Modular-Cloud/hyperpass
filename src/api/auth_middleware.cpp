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

#include "auth_middleware.h"

#include <boost/json.hpp>

namespace mp = multipass;
namespace json = boost::json;

bool mp::api::is_public_path(std::string_view path)
{
    // AtomOS Service requires Bearer on / and /version.
    // Probe extras and TLS fingerprint discovery stay public.
    return path == "/healthz" || path == "/readyz" || path == "/fingerprint" ||
           path == "/ca.crt" || path == "/api/v1/authenticate/cert";
}

bool mp::api::is_openai_inference_path(std::string_view path)
{
    return path == "/v1/models" || path.rfind("/v1/models/", 0) == 0 ||
           path == "/v1/chat/completions" || path == "/v1/completions" ||
           path == "/v1/embeddings";
}

mp::api::AuthResult mp::api::check_bearer_auth(std::string_view authorization_header,
                                               const ApiConfig& config)
{
    if (config.insecure_no_auth)
        return AuthResult::ok;

    constexpr std::string_view bearer_prefix = "Bearer ";
    if (authorization_header.size() <= bearer_prefix.size() ||
        authorization_header.substr(0, bearer_prefix.size()) != bearer_prefix)
        return AuthResult::missing;

    const auto token = authorization_header.substr(bearer_prefix.size());
    if (token != config.api_token)
        return AuthResult::invalid;

    return AuthResult::ok;
}

std::string mp::api::auth_error_body(AuthResult result)
{
    json::object body;
    body["error"] = result == AuthResult::missing ? "missing_token" : "invalid_token";
    body["message"] = result == AuthResult::missing
                          ? "Authorization Bearer token required"
                          : "Invalid Bearer token";
    return json::serialize(body);
}
