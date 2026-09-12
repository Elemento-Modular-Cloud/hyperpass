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

#include "spot_spec.h"

#include <multipass/format.h>

#include <QByteArray>

#include <algorithm>
#include <cctype>
#include <stdexcept>

namespace mp = multipass;
namespace json = boost::json;

namespace
{
std::string json_string_field(const json::object& obj,
                              std::string_view key,
                              std::string_view fallback = {})
{
    if (!obj.contains(key) || !obj.at(key).is_string())
        return std::string{fallback};
    return std::string(obj.at(key).as_string());
}

std::int64_t json_int_field(const json::object& obj, std::string_view key, std::int64_t fallback = 0)
{
    if (!obj.contains(key))
        return fallback;
    const auto& v = obj.at(key);
    if (v.is_int64())
        return v.as_int64();
    if (v.is_uint64())
        return static_cast<std::int64_t>(v.as_uint64());
    if (v.is_double())
        return static_cast<std::int64_t>(v.as_double());
    return fallback;
}

bool json_bool_field(const json::object& obj, std::string_view key, bool fallback)
{
    if (!obj.contains(key))
        return fallback;
    const auto& v = obj.at(key);
    if (v.is_bool())
        return v.as_bool();
    if (v.is_int64())
        return v.as_int64() != 0;
    return fallback;
}

const json::object& require_object(const json::object& body, std::string_view key)
{
    if (!body.contains(key) || !body.at(key).is_object())
        throw std::runtime_error(fmt::format("request was badly formatted. '{}'", key));
    return body.at(key).as_object();
}

std::string lowercase(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

mp::api::SpotVolume parse_volume(const json::value& value, std::string_view field)
{
    if (!value.is_object())
        throw std::runtime_error(fmt::format("request was badly formatted. '{}'", field));
    const auto& obj = value.as_object();
    mp::api::SpotVolume vol;
    vol.name = json_string_field(obj, "name");
    vol.size_gb = json_int_field(obj, "size_gb", 0);
    if (vol.size_gb <= 0)
        throw std::runtime_error(fmt::format("request was badly formatted. '{}.size_gb'", field));
    return vol;
}

std::vector<std::string> parse_string_array(const json::value& value)
{
    std::vector<std::string> out;
    if (!value.is_array())
        return out;
    for (const auto& item : value.as_array())
    {
        if (item.is_string())
            out.emplace_back(item.as_string());
    }
    return out;
}

mp::api::SpotAuth parse_auth(const json::object& obj)
{
    mp::api::SpotAuth auth;
    auth.username = json_string_field(obj, "username");
    auth.password = json_string_field(obj, "password");
    auth.ssh_key = json_string_field(obj, "ssh_key");
    if (auth.ssh_key.empty())
        auth.ssh_key = json_string_field(obj, "ssh-key");
    return auth;
}

void parse_startup(const json::object& body, mp::api::SpotSpec& spec, mp::api::SpotParseMode mode)
{
    if (body.contains("startup") && body.at("startup").is_object())
    {
        const auto& startup = body.at("startup").as_object();
        spec.startup_template = json_string_field(startup, "template");
        const auto b64 = json_string_field(startup, "b64_code");
        if (!b64.empty() && !startup.contains("template"))
        {
            spec.cloud_init_b64 = b64;
            spec.has_cloud_init_b64 = true;
        }
        else if (startup.contains("b64_code") && startup.at("b64_code").is_string() &&
                 spec.startup_template.empty())
        {
            spec.cloud_init_b64 = b64;
            spec.has_cloud_init_b64 = !b64.empty();
        }
    }

    if (body.contains("cloud_init_b64") && !body.at("cloud_init_b64").is_null())
    {
        if (body.at("cloud_init_b64").is_string())
        {
            spec.cloud_init_b64 = std::string(body.at("cloud_init_b64").as_string());
            spec.has_cloud_init_b64 = !spec.cloud_init_b64.empty();
        }
    }

    if (mode == mp::api::SpotParseMode::canallocate)
    {
        spec.auth = {};
        spec.cloud_init_b64.clear();
        spec.has_cloud_init_b64 = false;
        spec.startup_template.clear();
    }
}

void ensure_default_network(mp::api::SpotSpec& spec)
{
    if (spec.networks.empty())
    {
        mp::api::SpotNetwork net;
        net.kind = "natted";
        spec.networks.push_back(std::move(net));
    }
}

std::string version_from_release(std::string_view release)
{
    // "24.04 LTS", "Ubuntu 24.04.3 LTS", "24.04"
    std::string out;
    for (size_t i = 0; i + 4 < release.size(); ++i)
    {
        if (std::isdigit(static_cast<unsigned char>(release[i])) &&
            std::isdigit(static_cast<unsigned char>(release[i + 1])) && release[i + 2] == '.' &&
            std::isdigit(static_cast<unsigned char>(release[i + 3])) &&
            std::isdigit(static_cast<unsigned char>(release[i + 4])))
        {
            out.assign(release.substr(i, 5));
            break;
        }
    }
    return out;
}
} // namespace

mp::api::SpotSpec mp::api::parse_spot_spec(const json::object& body, SpotParseMode mode)
{
    SpotSpec spec;

    if (mode == SpotParseMode::register_vm)
    {
        spec.vm_name = json_string_field(body, "vm_name");
        if (spec.vm_name.empty())
            throw std::runtime_error("request was badly formatted. 'vm_name'");
        if (body.contains("auth") && body.at("auth").is_object())
            spec.auth = parse_auth(body.at("auth").as_object());
    }
    else if (body.contains("vm_name") && body.at("vm_name").is_string())
    {
        spec.vm_name = json_string_field(body, "vm_name");
    }

    const auto& cpu = require_object(body, "cpu");
    spec.cpu.slot_count = json_int_field(cpu, "slots", 0);
    if (spec.cpu.slot_count <= 0)
        throw std::runtime_error("request was badly formatted. 'cpu.slots'");
    spec.cpu.shared_cores = json_bool_field(cpu, "shared_cores", true);
    if (cpu.contains("arch"))
        spec.cpu.arch = parse_string_array(cpu.at("arch"));

    const auto& mem = require_object(body, "mem");
    spec.mem.capacity_mb = json_int_field(mem, "capacity_mb", 0);
    if (spec.mem.capacity_mb <= 0)
        throw std::runtime_error("request was badly formatted. 'mem.capacity_mb'");

    if (body.contains("os") && body.at("os").is_object())
    {
        const auto& os = body.at("os").as_object();
        spec.os.family = json_string_field(os, "family", "linux");
        spec.os.flavour = json_string_field(os, "flavour", "ubuntu");
        spec.os.version = json_string_field(os, "version");
    }
    if (mode == SpotParseMode::register_vm && spec.os.family.empty())
        throw std::runtime_error("request was badly formatted. 'os.family'");

    if (body.contains("storage") && body.at("storage").is_object())
    {
        const auto& storage = body.at("storage").as_object();
        if (storage.contains("boot"))
            spec.storage.boot = parse_volume(storage.at("boot"), "storage.boot");
        if (storage.contains("data") && storage.at("data").is_array())
        {
            for (const auto& item : storage.at("data").as_array())
                spec.storage.data.push_back(parse_volume(item, "storage.data"));
        }
    }
    if (mode == SpotParseMode::register_vm && spec.storage.boot.size_gb <= 0)
        throw std::runtime_error("request was badly formatted. 'storage.boot'");

    if (body.contains("pci") && body.at("pci").is_object())
    {
        const auto& pci = body.at("pci").as_object();
        if (pci.contains("devices") && pci.at("devices").is_array())
        {
            for (const auto& item : pci.at("devices").as_array())
            {
                if (!item.is_object())
                    continue;
                const auto& dev = item.as_object();
                SpotPciDevice parsed;
                parsed.vendor = json_string_field(dev, "vendor");
                parsed.model = json_string_field(dev, "model");
                parsed.quantity = json_int_field(dev, "quantity", 1);
                spec.pci_devices.push_back(std::move(parsed));
            }
        }
    }

    if (body.contains("networks") && body.at("networks").is_array())
    {
        for (const auto& item : body.at("networks").as_array())
        {
            if (!item.is_object())
                continue;
            const auto& net = item.as_object();
            SpotNetwork parsed;
            parsed.kind = json_string_field(net, "kind", "natted");
            parsed.network_uid = json_string_field(net, "network_uid");
            parsed.ipv4 = json_string_field(net, "ipv4");
            parsed.ipv6 = json_string_field(net, "ipv6");
            parsed.mac = json_string_field(net, "mac");
            if (net.contains("open_ports") && net.at("open_ports").is_array())
            {
                for (const auto& port_v : net.at("open_ports").as_array())
                {
                    if (!port_v.is_object())
                        continue;
                    const auto& port = port_v.as_object();
                    SpotOpenPort open;
                    open.protocol = json_string_field(port, "protocol", "tcp");
                    open.port = json_int_field(port, "port", 0);
                    if (port.contains("target_port"))
                        open.target_port = json_int_field(port, "target_port", 0);
                    parsed.open_ports.push_back(std::move(open));
                }
            }
            spec.networks.push_back(std::move(parsed));
        }
    }
    ensure_default_network(spec);

    if (body.contains("tags"))
        spec.tags = parse_string_array(body.at("tags"));

    parse_startup(body, spec, mode);

    return spec;
}

mp::api::SpotSpec mp::api::parse_spot_spec(std::string_view body, SpotParseMode mode)
{
    if (body.empty())
    {
        if (mode == SpotParseMode::canallocate)
        {
            SpotSpec spec;
            spec.cpu.slot_count = 0;
            spec.mem.capacity_mb = 0;
            return spec;
        }
        throw std::runtime_error("request was badly formatted. missing body");
    }

    const auto parsed = json::parse(body);
    if (!parsed.is_object())
        throw std::runtime_error("request was badly formatted. body must be a JSON object");
    return parse_spot_spec(parsed.as_object(), mode);
}

json::object mp::api::spec_to_public_json(const SpotSpec& spec)
{
    json::object cpu;
    cpu["slots"] = spec.cpu.slot_count;
    cpu["shared_cores"] = spec.cpu.shared_cores;
    json::array arch;
    for (const auto& a : spec.cpu.arch)
        arch.emplace_back(a);
    cpu["arch"] = std::move(arch);

    json::object mem;
    mem["capacity_mb"] = spec.mem.capacity_mb;

    json::object os;
    os["family"] = spec.os.family;
    os["flavour"] = spec.os.flavour;
    if (!spec.os.version.empty())
        os["version"] = spec.os.version;

    json::object boot;
    boot["name"] = spec.storage.boot.name;
    boot["size_gb"] = spec.storage.boot.size_gb;
    json::array data;
    for (const auto& vol : spec.storage.data)
    {
        json::object item;
        item["name"] = vol.name;
        item["size_gb"] = vol.size_gb;
        data.push_back(std::move(item));
    }
    json::object storage;
    storage["boot"] = std::move(boot);
    storage["data"] = std::move(data);

    json::array devices;
    for (const auto& dev : spec.pci_devices)
    {
        json::object item;
        item["vendor"] = dev.vendor;
        item["model"] = dev.model;
        item["quantity"] = dev.quantity;
        devices.push_back(std::move(item));
    }
    json::object pci;
    pci["devices"] = std::move(devices);

    json::array networks;
    for (const auto& net : spec.networks)
    {
        json::object item;
        item["kind"] = net.kind;
        if (!net.network_uid.empty())
            item["network_uid"] = net.network_uid;
        if (!net.open_ports.empty())
        {
            json::array ports;
            for (const auto& port : net.open_ports)
            {
                json::object p;
                p["protocol"] = port.protocol;
                p["port"] = port.port;
                if (port.target_port)
                    p["target_port"] = *port.target_port;
                ports.push_back(std::move(p));
            }
            item["open_ports"] = std::move(ports);
        }
        if (!net.ipv4.empty())
            item["ipv4"] = net.ipv4;
        else
            item["ipv4"] = nullptr;
        item["ipv6"] = net.ipv6.empty() ? json::value(nullptr) : json::value(net.ipv6);
        item["mac"] = net.mac.empty() ? json::value(nullptr) : json::value(net.mac);
        networks.push_back(std::move(item));
    }

    json::array tags;
    for (const auto& tag : spec.tags)
        tags.emplace_back(tag);

    json::object out;
    if (!spec.vm_name.empty())
        out["vm_name"] = spec.vm_name;
    out["cpu"] = std::move(cpu);
    out["mem"] = std::move(mem);
    out["os"] = std::move(os);
    out["storage"] = std::move(storage);
    out["pci"] = std::move(pci);
    out["networks"] = std::move(networks);
    out["tags"] = std::move(tags);
    if (!spec.startup_template.empty())
    {
        json::object startup;
        startup["kind"] = "cloud-init";
        startup["template"] = spec.startup_template;
        out["startup"] = std::move(startup);
    }
    return out;
}

mp::api::SpotSpec mp::api::spec_from_daemon_fields(std::string_view vm_name,
                                                   std::string_view current_release,
                                                   std::string_view os,
                                                   std::string_view service_id)
{
    SpotSpec spec;
    spec.vm_name = std::string{vm_name};
    spec.cpu.slot_count = 0;
    spec.mem.capacity_mb = 0;
    spec.os.family = os.empty() ? "linux" : lowercase(std::string{os});
    spec.os.flavour = "ubuntu";
    spec.os.version = version_from_release(current_release);
    if (spec.os.version.empty() && !current_release.empty())
        spec.os.flavour = std::string{current_release};
    spec.storage.boot.name = "root";
    spec.storage.boot.size_gb = 0;
    if (!service_id.empty())
    {
        spec.startup_template = std::string{service_id};
        spec.tags.push_back(fmt::format("service:{}", service_id));
    }
    ensure_default_network(spec);
    return spec;
}

mp::api::LaunchSpec mp::api::launch_spec_from_spot(const SpotSpec& spec, std::string cloud_init_user_data)
{
    LaunchSpec launch;
    launch.instance_name = spec.vm_name;
    if (!spec.os.version.empty())
        launch.image = spec.os.version;
    else
    {
        auto flavour = lowercase(spec.os.flavour);
        launch.image = flavour.empty() ? "ubuntu" : flavour;
    }
    launch.num_cores = static_cast<int>(std::max<std::int64_t>(spec.cpu.slot_count, 1));
    launch.mem_size = fmt::format("{}M", std::max<std::int64_t>(spec.mem.capacity_mb, 512));
    const auto disk_gb = spec.storage.boot.size_gb > 0 ? spec.storage.boot.size_gb : 5;
    launch.disk_space = fmt::format("{}G", disk_gb);
    launch.cloud_init_user_data = std::move(cloud_init_user_data);
    launch.service_id = service_id_from_spec(spec);
    return launch;
}

std::string mp::api::decode_cloud_init_b64(std::string_view b64)
{
    const auto decoded = QByteArray::fromBase64(QByteArray::fromRawData(b64.data(), static_cast<int>(b64.size())),
                                                QByteArray::Base64Encoding);
    if (decoded.isEmpty() && !b64.empty())
        throw std::runtime_error("request was badly formatted. 'cloud_init_b64'");
    return decoded.toStdString();
}

std::string mp::api::merge_auth_into_cloud_init(std::string user_data, const SpotAuth& auth)
{
    if (auth.username.empty() && auth.password.empty() && auth.ssh_key.empty())
        return user_data;

    std::string generated = "#cloud-config\nusers:\n";
    generated += fmt::format("  - name: {}\n", auth.username.empty() ? "ubuntu" : auth.username);
    generated += "    sudo: ALL=(ALL) NOPASSWD:ALL\n";
    generated += "    shell: /bin/bash\n";
    if (!auth.password.empty())
        generated += fmt::format("    plain_text_passwd: \"{}\"\n    lock_passwd: false\n", auth.password);
    if (!auth.ssh_key.empty())
    {
        generated += "    ssh_authorized_keys:\n";
        generated += fmt::format("      - {}\n", auth.ssh_key);
    }

    if (user_data.empty())
        return generated;

    auto rest = user_data;
    constexpr std::string_view header = "#cloud-config";
    if (rest.rfind(header, 0) == 0)
        rest = rest.substr(header.size());
    while (!rest.empty() && (rest.front() == '\n' || rest.front() == '\r'))
        rest.erase(rest.begin());
    if (!rest.empty())
        generated += rest;
    if (!generated.empty() && generated.back() != '\n')
        generated.push_back('\n');
    return generated;
}

std::string mp::api::service_id_from_spec(const SpotSpec& spec)
{
    if (!spec.startup_template.empty())
        return spec.startup_template;
    constexpr std::string_view prefix = "service:";
    for (const auto& tag : spec.tags)
    {
        if (tag.rfind(prefix, 0) == 0 && tag.size() > prefix.size())
            return tag.substr(prefix.size());
    }
    return {};
}

std::int64_t mp::api::first_open_port(const SpotSpec& spec)
{
    for (const auto& net : spec.networks)
    {
        for (const auto& port : net.open_ports)
        {
            if (port.port > 0)
                return port.port;
        }
    }
    return 0;
}

bool mp::api::can_place_spot(const SpotSpec& spec,
                             std::int64_t available_mib,
                             std::int64_t available_slots)
{
    if (!can_allocate_from_available(available_mib, spec.mem.capacity_mb))
        return false;
    if (spec.cpu.slot_count > 0 && available_slots >= 0 && spec.cpu.slot_count > available_slots)
        return false;
    return true;
}
