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

#include <boost/json.hpp>

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace multipass::api
{

struct SpotCpu
{
    std::int64_t slot_count{1};
    bool shared_cores{true};
    std::vector<std::string> arch;
};

struct SpotMem
{
    std::int64_t capacity_mb{1024};
};

struct SpotOs
{
    std::string family{"linux"};
    std::string flavour{"ubuntu"};
    std::string version;
};

struct SpotVolume
{
    std::string name;
    std::int64_t size_gb{0};
};

struct SpotStorage
{
    SpotVolume boot;
    std::vector<SpotVolume> data;
};

struct SpotPciDevice
{
    std::string vendor;
    std::string model;
    std::int64_t quantity{1};
};

struct SpotOpenPort
{
    std::string protocol{"tcp"};
    std::int64_t port{0};
    std::optional<std::int64_t> target_port;
};

struct SpotNetwork
{
    std::string kind{"natted"};
    std::string network_uid;
    std::vector<SpotOpenPort> open_ports;
    std::string ipv4;
    std::string ipv6;
    std::string mac;
};

struct SpotAuth
{
    std::string username;
    std::string password;
    std::string ssh_key;
};

struct SpotSpec
{
    std::string vm_name;
    SpotCpu cpu;
    SpotMem mem;
    SpotOs os;
    SpotStorage storage;
    std::vector<SpotPciDevice> pci_devices;
    std::vector<SpotNetwork> networks;
    SpotAuth auth;
    std::vector<std::string> tags;
    std::string cloud_init_b64; // decoded later; empty means absent/null
    bool has_cloud_init_b64{false};
    std::string startup_template;
    std::string region{"local"};
};

enum class SpotParseMode
{
    register_vm,
    canallocate
};

/** Parse a Spot v2 JSON object. Throws std::runtime_error on bad input. */
SpotSpec parse_spot_spec(const boost::json::object& body, SpotParseMode mode);

/** Parse JSON text. Empty canallocate body means “any remaining RAM”. */
SpotSpec parse_spot_spec(std::string_view body, SpotParseMode mode);

/** v2 running/registry shape: no auth secrets, no cloud_init_b64. */
boost::json::object spec_to_public_json(const SpotSpec& spec);

LaunchSpec launch_spec_from_spot(const SpotSpec& spec, std::string cloud_init_user_data);

/** Synthesize a v2 spec from daemon list fields (cpu/mem/disk unknown → 0). */
SpotSpec spec_from_daemon_fields(std::string_view vm_name,
                                 std::string_view current_release,
                                 std::string_view os,
                                 std::string_view service_id);

/** Decode standard base64 cloud-init. Throws if the payload is invalid. */
std::string decode_cloud_init_b64(std::string_view b64);

/** Merge auth into user-data (minimal users block when user-data is empty). */
std::string merge_auth_into_cloud_init(std::string user_data, const SpotAuth& auth);

/** service:<id> tag, else startup.template. */
std::string service_id_from_spec(const SpotSpec& spec);

std::int64_t first_open_port(const SpotSpec& spec);

inline bool can_allocate_from_available(std::int64_t available_mib, std::int64_t requested_mib)
{
    return requested_mib <= 0 ? available_mib > 0 : available_mib >= requested_mib;
}

bool can_place_spot(const SpotSpec& spec,
                    std::int64_t available_mib,
                    std::int64_t available_slots);

} // namespace multipass::api
