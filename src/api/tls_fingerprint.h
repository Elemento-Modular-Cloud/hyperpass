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

#include <string>
#include <string_view>

namespace multipass::api
{

/** AtomOS matcher TLS port used by Electros for fingerprint fetch. */
constexpr int atomos_matcher_tls_port = 7777;
/** AtomOS storage TLS fallback port used by Electros for fingerprint fetch. */
constexpr int atomos_storage_tls_port = 7772;

struct RemoteCertInfo
{
    std::string fingerprint; // AtomOS colon-separated SHA-256
    bool validated{false};   // true if system CA / hostname verify succeeds
};

/**
 * AtomOS / Electros authenticator fingerprint:
 * uppercase SHA-256 of the certificate DER, bytes joined with ':'.
 * Matches elemento-authenticator-client get_fingerprint().
 */
std::string fingerprint_from_der(std::string_view der);

/** Parse a PEM certificate and return its AtomOS fingerprint. Throws on error. */
std::string fingerprint_from_pem(std::string_view pem);

/** Load a PEM certificate file and return its AtomOS fingerprint. Throws on error. */
std::string fingerprint_from_pem_file(const std::string& path);

/**
 * Electros-compatible remote cert probe: TLS connect to host:port (no HTTP),
 * SHA-256 fingerprint of the peer cert DER. `validated` mirrors Electros'
 * second connection with hostname + CA verification.
 * Throws std::runtime_error on connect/handshake failure.
 */
RemoteCertInfo fetch_remote_tls_cert(const std::string& host, int port, int timeout_sec = 5);

/**
 * Try matcher port 7777 then storage 7772 (Electros get_cert fallback).
 * Throws if both fail.
 */
RemoteCertInfo fetch_remote_tls_cert_atomos(const std::string& host, int timeout_sec = 5);

} // namespace multipass::api
