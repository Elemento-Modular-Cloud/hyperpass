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

#include <multipass/logging/level.h>

#include <string>
#include <vector>

namespace multipass::api
{

struct ApiConfig
{
    std::string listen_address;   // host[,host…]:port
    std::string daemon_address;   // unix:… or host:port
    std::string api_token;        // empty when insecure_no_auth
    bool insecure_no_auth{false};
    bool include_multipass{true}; // discover/list stock Multipass instances
    std::string multipass_address; // optional override (else discover)
    logging::Level verbosity_level{logging::Level::info};

    // HTTPS / AtomOS fingerprint verification (default on — Electros dials TLS on :7777)
    bool use_https{true};
    std::string cert_file; // optional PEM path (with key_file)
    std::string key_file;
    std::string cert_pem;         // resolved leaf material
    std::string key_pem;
    std::string ca_pem;           // CA (or leaf, when operator-supplied) for GET /ca.crt
    std::string tls_fingerprint;  // AtomOS SHA-256 colon form of the leaf
};

struct ListenEndpoint
{
    std::vector<std::string> hosts;
    int port{0};
};

/**
 * Parse CLI args and environment into an ApiConfig.
 * Requires a live QCoreApplication (for argument/env access). Throws on invalid input.
 */
ApiConfig parse_config();

/**
 * Load or auto-generate HTTPS PEMs and compute the AtomOS TLS fingerprint.
 * No-op when use_https is false (--http).
 */
void prepare_tls(ApiConfig& config);

/**
 * Parse "host:port" or "host1,host2:port" into hosts + port. Throws if malformed.
 */
ListenEndpoint parse_listen_endpoint(const std::string& listen);

/** Split a single "host:port" into host and port. Throws if malformed. */
void parse_listen_address(const std::string& listen, std::string& host, int& port);

} // namespace multipass::api
