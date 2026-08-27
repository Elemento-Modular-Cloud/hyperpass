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

#include <grpcpp/grpcpp.h>

#include <memory>
#include <optional>
#include <string>

namespace multipass::api
{

struct MultipassConnection
{
    std::string address; // unix:… or host:port
    std::string root_cert_pem;
    std::string client_cert_pem;
    std::string client_key_pem;
};

/**
 * Discover a stock Multipass daemon (same layout as the GUI's multipass_discovery.dart).
 * Returns nullopt when Multipass does not appear installed / reachable.
 *
 * @param address_override  optional HYPERPASS_MULTIPASS_ADDRESS / --multipass-address value
 */
std::optional<MultipassConnection> discover_multipass_connection(
    const std::string& address_override = {});

/** Build an mTLS gRPC channel using explicit PEM material (for Multipass). */
std::shared_ptr<grpc::Channel> make_channel_with_pems(const std::string& server_address,
                                                      const std::string& root_cert_pem,
                                                      const std::string& client_cert_pem,
                                                      const std::string& client_key_pem);

/** Default Multipass listen address for the current platform (no file checks). */
std::string default_multipass_server_address();

} // namespace multipass::api
