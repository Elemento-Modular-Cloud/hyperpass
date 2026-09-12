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

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace multipass::api
{

struct MarketplaceFileSpec
{
    std::string source;
    std::string destination;
    std::string owner{"root:root"};
    std::string permissions{"0644"};
};

struct MarketplaceService
{
    std::string id;
    std::string version;
    std::string entrypoint{"cloud-init.yaml"};
    std::vector<MarketplaceFileSpec> files;
    std::vector<std::int64_t> ingress_ports;
    std::unordered_map<std::string, std::string> sources;
};

struct MarketplaceLibrary
{
    std::vector<MarketplaceService> services;

    const MarketplaceService* lookup(std::string_view id) const;
};

/** Family id without a trailing `_v<N>` suffix (`n8n_v3` → `n8n`). */
std::string marketplace_service_family(std::string_view service_id);

/**
 * Load from ELP_MARKETPLACE_DIR (clone or services/) or ELP_MARKETPLACE_URL
 * (JSON bundle or local file path). Throws if neither is configured or load fails.
 */
MarketplaceLibrary load_marketplace_library();

/**
 * Render a service directory into a single #cloud-config document.
 * Placeholders are left unsubstituted. Optional CA PEM is written for the guest.
 */
std::string render_marketplace_cloud_init(const MarketplaceService& service,
                                          std::string_view gateway_ca_pem = {});

std::int64_t first_marketplace_ingress_port(const MarketplaceService& service);

} // namespace multipass::api
