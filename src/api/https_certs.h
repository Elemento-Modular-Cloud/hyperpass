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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */

#pragma once

#include <string>
#include <vector>

#include <QString>

namespace multipass::api
{

/** Auto-generated HTTPS material: local CA plus a serverAuth leaf. */
struct HttpsCertMaterial
{
    std::string ca_pem;
    std::string cert_pem;
    std::string key_pem;
};

/**
 * Load a previously generated CA + server pair from [cert_dir], or mint a new
 * one. Reuses existing files only when the leaf has serverAuth EKU (ignores
 * leftover gRPC client certs named elp_cert.pem).
 *
 * SAN always includes DNS:localhost, IP:127.0.0.1, IP:192.168.67.1, plus
 * [listen_hosts] classified as IP or DNS.
 */
HttpsCertMaterial load_or_create_https_certs(const QString& cert_dir,
                                             const std::vector<std::string>& listen_hosts);

} // namespace multipass::api
