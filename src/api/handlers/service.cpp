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

#include "service.h"
#include "handlers.h"

#include <boost/json.hpp>

#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/utils.h>
#include <multipass/version.h>

#include <algorithm>
#include <cctype>
#include <optional>
#include <string>
#include <unordered_map>

namespace mpl = multipass::logging;

namespace mp = multipass;
namespace json = boost::json;

namespace
{
constexpr auto service_category = "api-service";
constexpr auto backend_name = "hyperpass";

std::string json_string_field(const json::object& obj, std::string_view key, std::string_view fallback = {})
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

std::int64_t parse_requested_mib(std::string_view body)
{
    if (body.empty())
        return 0;
    try
    {
        const auto parsed = json::parse(body);
        if (!parsed.is_object())
            return 0;
        const auto& obj = parsed.as_object();
        std::int64_t requested_mib = 0;
        if (obj.contains("req") && obj.at("req").is_object())
        {
            const auto& req_obj = obj.at("req").as_object();
            if (req_obj.contains("mem") && req_obj.at("mem").is_object())
                requested_mib = json_int_field(req_obj.at("mem").as_object(), "capacity", 0);
        }
        if (requested_mib == 0)
            requested_mib = json_int_field(obj, "memory_mib", 0);
        if (requested_mib == 0)
            requested_mib = json_int_field(obj, "ram", 0);
        return requested_mib;
    }
    catch (const std::exception&)
    {
        return 0;
    }
}

bool json_truthy(const json::value& v)
{
    if (v.is_bool())
        return v.as_bool();
    if (v.is_int64())
        return v.as_int64() != 0;
    if (v.is_string())
    {
        auto s = std::string(v.as_string());
        std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return std::tolower(c); });
        return s == "true" || s == "1" || s == "yes";
    }
    return false;
}

std::optional<json::object> parse_object_body(const httplib::Request& req, httplib::Response& res)
{
    if (req.body.empty())
    {
        json::object body;
        body["error"] = "request was badly formatted. missing body";
        res.status = 400;
        res.set_content(json::serialize(body), "application/json");
        return std::nullopt;
    }

    try
    {
        const auto parsed = json::parse(req.body);
        if (!parsed.is_object())
        {
            json::object body;
            body["error"] = "request was badly formatted. body must be a JSON object";
            res.status = 400;
            res.set_content(json::serialize(body), "application/json");
            return std::nullopt;
        }
        return parsed.as_object();
    }
    catch (const std::exception& e)
    {
        json::object body;
        body["error"] = fmt::format("request was badly formatted. {}", e.what());
        res.status = 400;
        res.set_content(json::serialize(body), "application/json");
        return std::nullopt;
    }
}

void set_json(httplib::Response& res, int status, const json::value& body)
{
    res.status = status;
    res.set_content(json::serialize(body), "application/json");
}

void set_daemon_error(httplib::Response& res, const grpc::Status& status)
{
    if (status.error_code() == grpc::StatusCode::UNAVAILABLE)
    {
        json::object body;
        body["error"] = "hyperpass backend unreachable";
        body["message"] = status.error_message();
        set_json(res, 503, body);
        return;
    }
    if (status.error_code() == grpc::StatusCode::NOT_FOUND)
    {
        json::object body;
        body["error"] = "not_found";
        body["message"] = status.error_message();
        set_json(res, 404, body);
        return;
    }
    if (status.error_code() == grpc::StatusCode::INVALID_ARGUMENT ||
        status.error_code() == grpc::StatusCode::FAILED_PRECONDITION)
    {
        json::object body;
        body["error"] = status.error_message();
        set_json(res, 400, body);
        return;
    }

    json::object body;
    body["error"] = "internal_error";
    body["message"] = status.error_message();
    body["code"] = static_cast<std::int64_t>(status.error_code());
    set_json(res, 500, body);
}

std::string instance_status_name(const mp::InstanceStatus& status)
{
    switch (status.status())
    {
    case mp::InstanceStatus::RUNNING:
        return "running";
    case mp::InstanceStatus::STOPPED:
        return "stopped";
    case mp::InstanceStatus::DELETED:
        return "deleted";
    case mp::InstanceStatus::STARTING:
        return "starting";
    case mp::InstanceStatus::RESTARTING:
        return "restarting";
    case mp::InstanceStatus::DELAYED_SHUTDOWN:
        return "delayed_shutdown";
    case mp::InstanceStatus::SUSPENDING:
        return "suspending";
    case mp::InstanceStatus::SUSPENDED:
        return "suspended";
    case mp::InstanceStatus::UNAVAILABLE:
        return "unavailable";
    case mp::InstanceStatus::UNKNOWN:
    default:
        return "unknown";
    }
}

std::string image_for_flavour(std::string_view flavour)
{
    std::string lower{flavour};
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });

    if (lower == "ubuntu" || lower.empty())
        return "ubuntu";
    if (lower == "debian")
        return "debian";
    if (lower == "fedora")
        return "fedora";
    if (lower == "centos")
        return "centos";
    return lower;
}

std::string build_cloud_init(const json::object& body)
{
    std::string user_data;
    if (body.contains("startup") && body.at("startup").is_object())
    {
        const auto& startup = body.at("startup").as_object();
        const auto tech = json_string_field(startup, "technology");
        if (!tech.empty() && tech != "cloud-init")
            throw std::runtime_error(fmt::format("unknown startup.technology '{}'", tech));
        user_data = json_string_field(startup, "user_data");
    }

    std::string username;
    std::string password;
    std::string ssh_key;
    if (body.contains("authentication") && body.at("authentication").is_object())
    {
        const auto& auth = body.at("authentication").as_object();
        username = json_string_field(auth, "username");
        password = json_string_field(auth, "password");
        ssh_key = json_string_field(auth, "ssh-key");
        if (ssh_key.empty())
            ssh_key = json_string_field(auth, "ssh_key");
    }

    if (username.empty() && password.empty() && ssh_key.empty())
        return user_data;

    // Merge a minimal users block ahead of optional caller user-data.
    std::string generated = "#cloud-config\nusers:\n";
    generated += fmt::format("  - name: {}\n", username.empty() ? "ubuntu" : username);
    generated += "    sudo: ALL=(ALL) NOPASSWD:ALL\n";
    generated += "    shell: /bin/bash\n";
    if (!password.empty())
        generated += fmt::format("    plain_text_passwd: \"{}\"\n    lock_passwd: false\n", password);
    if (!ssh_key.empty())
    {
        generated += "    ssh_authorized_keys:\n";
        generated += fmt::format("      - {}\n", ssh_key);
    }

    if (!user_data.empty())
    {
        // Strip leading #cloud-config from caller data to avoid duplicate headers.
        auto rest = user_data;
        constexpr std::string_view header = "#cloud-config";
        if (rest.rfind(header, 0) == 0)
            rest = rest.substr(header.size());
        while (!rest.empty() && (rest.front() == '\n' || rest.front() == '\r'))
            rest.erase(rest.begin());
        if (!rest.empty())
            generated += rest;
        if (generated.back() != '\n')
            generated.push_back('\n');
    }

    return generated;
}

std::string flavour_from_os(std::string_view os, std::string_view release)
{
    std::string lower_os{os};
    std::transform(lower_os.begin(), lower_os.end(), lower_os.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    if (lower_os.find("ubuntu") != std::string::npos)
        return "ubuntu";
    if (lower_os.find("debian") != std::string::npos)
        return "debian";
    if (lower_os.find("fedora") != std::string::npos)
        return "fedora";
    if (!release.empty())
        return std::string{release};
    return lower_os.empty() ? "linux" : lower_os;
}

/** Ensure req_json fields Electros VmModel.fromJSON requires are present/typed. */
json::object electros_safe_req_json(json::object req)
{
    auto ensure_array = [&req](std::string_view key) {
        if (!req.contains(key) || !req.at(key).is_array())
            req[key] = json::array{};
    };
    ensure_array("networks");
    ensure_array("pcidevs");
    ensure_array("netdevs");
    ensure_array("flags");

    json::array safe_vols;
    if (req.contains("volumes") && req.at("volumes").is_array())
    {
        for (const auto& v : req.at("volumes").as_array())
        {
            if (!v.is_object())
                continue;
            auto vol = v.as_object();
            if (!vol.contains("lastUpdated") || !vol.at("lastUpdated").is_string())
                vol["lastUpdated"] = "";
            if (!vol.contains("cache") || !vol.at("cache").is_object())
            {
                json::object cache;
                cache["partitions"] = json::array{};
                vol["cache"] = std::move(cache);
            }
            else
            {
                auto& cache = vol.at("cache").as_object();
                if (!cache.contains("partitions") || !cache.at("partitions").is_array())
                    cache["partitions"] = json::array{};
            }
            safe_vols.push_back(std::move(vol));
        }
    }
    req["volumes"] = std::move(safe_vols);

    if (!req.contains("viewer"))
        req["viewer"] = nullptr;
    if (!req.contains("domviewer"))
        req["domviewer"] = nullptr;
    if (!req.contains("network_config"))
        req["network_config"] = nullptr;
    if (!req.contains("states"))
        req["states"] = "running";

    return req;
}

bool is_electros_req_json(const json::object& req)
{
    return req.contains("vm_name") && req.contains("os_family");
}

/** Build Electros VmModel req_json from matcher systemrequirements or an existing req_json. */
json::object build_electros_req_json(json::object req_or_sys,
                                     std::string_view vm_name,
                                     std::string_view os_family,
                                     std::string_view os_flavour,
                                     const json::array& volumes,
                                     const json::array& networks,
                                     bool autostart,
                                     std::string_view state,
                                     std::string_view guest_ipv4 = {})
{
    if (is_electros_req_json(req_or_sys))
    {
        if (!req_or_sys.contains("states"))
            req_or_sys["states"] = state;
        if (!volumes.empty() &&
            (!req_or_sys.contains("volumes") || !req_or_sys.at("volumes").is_array() ||
             req_or_sys.at("volumes").as_array().empty()))
            req_or_sys["volumes"] = volumes;
        if (!networks.empty() &&
            (!req_or_sys.contains("networks") || !req_or_sys.at("networks").is_array() ||
             req_or_sys.at("networks").as_array().empty()))
            req_or_sys["networks"] = networks;
        return electros_safe_req_json(std::move(req_or_sys));
    }

    json::object misc;
    json::object cpu;
    json::object mem;
    if (req_or_sys.contains("misc") && req_or_sys.at("misc").is_object())
        misc = req_or_sys.at("misc").as_object();
    if (req_or_sys.contains("cpu") && req_or_sys.at("cpu").is_object())
        cpu = req_or_sys.at("cpu").as_object();
    if (req_or_sys.contains("mem") && req_or_sys.at("mem").is_object())
        mem = req_or_sys.at("mem").as_object();

    const auto family =
        os_family.empty() ? json_string_field(misc, "os_family", "linux") : std::string{os_family};
    const auto flavour = os_flavour.empty() ? json_string_field(misc, "os_flavour", family)
                                            : std::string{os_flavour};

    const auto cpu_slots = json_int_field(cpu, "slots", 1);
    const auto capacity_mb = json_int_field(mem, "capacity", 1024);
    const auto ramsize_gb = std::max<std::int64_t>((capacity_mb + 1023) / 1024, 1);

    json::object req;
    req["vm_name"] = vm_name;
    req["states"] = state;
    req["slots"] = cpu_slots;
    req["ramsize"] = ramsize_gb;
    req["os_family"] = family;
    req["os_flavour"] = flavour;
    req["creation_date"] = "";
    req["autostart"] = autostart;
    req["firmware"] = json_string_field(misc, "firmware", "bios");
    req["qemu_agent"] = misc.contains("qemu_agent") ? json_truthy(misc.at("qemu_agent")) : false;
    req["allowSMT"] = false;
    req["arch"] = "";
    req["flags"] =
        cpu.contains("flags") && cpu.at("flags").is_array() ? cpu.at("flags") : json::array{};
    req["netdevs"] = json::array{};
    req["overprovision"] = json_int_field(cpu, "maxOverprovision", 0);
    req["reqECC"] = mem.contains("requireECC") ? json_truthy(mem.at("requireECC")) : false;
    req["viewer"] = nullptr;
    req["domviewer"] = nullptr;
    req["pcidevs"] = json::array{};
    req["volumes"] = volumes;
    req["networks"] = networks;

    if (!guest_ipv4.empty())
    {
        json::object nc;
        nc["interface"] = "";
        nc["mac"] = "";
        nc["ipv4"] = guest_ipv4;
        nc["is_reachable_from_host"] = false;
        nc["model"] = "";
        nc["name"] = "";
        nc["source"] = "";
        nc["type"] = "";
        json::object dom;
        dom["port"] = 5900;
        dom["protocol"] = "vnc";
        nc["dom_display"] = std::move(dom);
        req["network_config"] = std::move(nc);
    }
    else
    {
        req["network_config"] = nullptr;
    }

    return electros_safe_req_json(std::move(req));
}

json::object synthesize_req_json(const mp::api::RegisteredVm& recorded,
                                 std::string_view state = "running",
                                 std::string_view guest_ipv4 = {})
{
    json::object req_or_sys;
    if (!recorded.req_json.empty())
    {
        try
        {
            const auto parsed = json::parse(recorded.req_json);
            if (parsed.is_object())
                req_or_sys = parsed.as_object();
        }
        catch (const std::exception&)
        {
        }
    }

    return build_electros_req_json(std::move(req_or_sys),
                                   recorded.vm_name,
                                   recorded.os_family,
                                   recorded.os_flavour,
                                   json::array{},
                                   json::array{},
                                   false,
                                   state,
                                   guest_ipv4);
}

std::string domain_xml_for(const mp::api::RegisteredVm& recorded)
{
    if (!recorded.xml.empty())
        return recorded.xml;
    return fmt::format("<domain type='hyperpass'><name>{}</name><uuid>{}</uuid></domain>",
                       recorded.vm_name,
                       recorded.vm_uid);
}
} // namespace

void mp::api::register_service_handlers(httplib::Server& server,
                                        GrpcBackend& hyperpass_backend,
                                        VmRegistry& registry)
{
    server.Get("/", [&hyperpass_backend](const httplib::Request&, httplib::Response& res) {
        if (!hyperpass_backend.ping())
        {
            set_json(res, 503, json::object{{"error", "hyperpass backend unreachable"}});
            return;
        }
        res.status = 200;
        res.set_content("OK", "text/plain");
    });

    server.Get("/version", [&hyperpass_backend](const httplib::Request&, httplib::Response& res) {
        json::object body;
        body["version"] = multipass::version_string;
        body["backend"] = backend_name;

        const auto ver = hyperpass_backend.version();
        if (ver.status.ok())
            body["backend_version"] = ver.reply.version();
        else
            body["backend_version"] = multipass::version_string;

        set_json(res, 200, body);
    });

    // Matcher canallocate — Electros discovery; remaining ResourcePool RAM in MiB.
    const httplib::Server::Handler canallocate_handler =
        [&hyperpass_backend](const httplib::Request& req, httplib::Response& res) {
            mpl::log(mpl::Level::debug,
                     service_category,
                     "canallocate from {} ({} bytes)",
                     req.remote_addr,
                     req.body.size());

            if (!hyperpass_backend.ping())
            {
                set_json(res, 503, json::object{{"error", "hyperpass backend unreachable"},
                                                {"canallocate", false}});
                return;
            }

            const auto info = hyperpass_backend.daemon_info();
            if (!info.status.ok())
            {
                set_json(res, 503, json::object{{"error", info.status.error_message()},
                                                {"canallocate", false}});
                return;
            }

            const auto available_mib =
                static_cast<std::int64_t>(info.reply.memory_available() / (1024 * 1024));
            const auto requested_mib = mp::api::requested_mib_from_canallocate_body(req.body);
            const bool can = mp::api::can_allocate_from_available(available_mib, requested_mib);
            json::object out;
            out["canallocate"] = can;
            out["available_slots"] = std::max<std::int64_t>(
                0,
                static_cast<std::int64_t>(info.reply.cpus()) - info.reply.cpus_claimed());
            out["available_ram"] = available_mib;
            // Electros substitutes discovery URLs itself; include a hint for gateways.
            out["server_url"] = fmt::format("https://{}:{}",
                                            req.local_addr.empty() ? "127.0.0.1" : req.local_addr,
                                            req.local_port > 0 ? req.local_port : 7777);
            out["nservers"] = 1;
            set_json(res, 200, out);
        };
    server.Get("/api/v1.0/canallocate", canallocate_handler);
    server.Post("/api/v1.0/canallocate", canallocate_handler);

    server.Post("/api/v1.0/canallocate/multiple",
                [&hyperpass_backend](const httplib::Request& req, httplib::Response& res) {
                    mpl::log(mpl::Level::debug,
                             service_category,
                             "canallocate/multiple from {} ({} bytes)",
                             req.remote_addr,
                             req.body.size());
                    if (!hyperpass_backend.ping())
                    {
                        set_json(res,
                                 503,
                                 json::object{{"error", "hyperpass backend unreachable"},
                                              {"canallocate", false}});
                        return;
                    }
                    const auto info = hyperpass_backend.daemon_info();
                    json::object out;
                    out["canallocate"] = info.status.ok() && info.reply.memory_available() > 0;
                    out["available_ram"] =
                        static_cast<std::int64_t>(info.reply.memory_available() / (1024 * 1024));
                    out["nservers"] = 1;
                    set_json(res, 200, out);
                });

    // AtomOS names (register/running/unregister) and Meson aliases
    // (create_machine/get_machine/delete_machine) share the same handlers.
    const httplib::Server::Handler register_or_create =
        [&hyperpass_backend, &registry](const httplib::Request& req, httplib::Response& res) {
            const auto body_opt = parse_object_body(req, res);
            if (!body_opt)
                return;
            const auto& body = *body_opt;

            try
            {
                const auto client_uid = json_string_field(body, "client_uid");
                auto vm_name = json_string_field(body, "vm_name");
                if (client_uid.empty())
                    throw std::runtime_error("request was badly formatted. 'client_uid'");
                // Electros matcher-client often omits vm_name unless info.vm_name is set.
                if (vm_name.empty())
                    vm_name = fmt::format("hp-{}", mp::utils::make_uuid().substr(0, 8));
                if (!body.contains("req") || !body.at("req").is_object())
                    throw std::runtime_error("request was badly formatted. 'req'");
                // Matcher may send empty volumes when storage is unused; allow with a default disk.
                json::array volumes;
                if (body.contains("volumes") && body.at("volumes").is_array())
                    volumes = body.at("volumes").as_array();
                json::array networks;
                if (body.contains("networks") && body.at("networks").is_array())
                    networks = body.at("networks").as_array();
                const auto autostart =
                    body.contains("autostart") && json_truthy(body.at("autostart"));

                const auto& req_obj = body.at("req").as_object();
                if (!req_obj.contains("cpu") || !req_obj.at("cpu").is_object())
                    throw std::runtime_error("request was badly formatted. 'req.cpu'");
                if (!req_obj.contains("mem") || !req_obj.at("mem").is_object())
                    throw std::runtime_error("request was badly formatted. 'req.mem'");
                // misc is optional for some Electros encodings; default linux/ubuntu.
                json::object misc;
                if (req_obj.contains("misc") && req_obj.at("misc").is_object())
                    misc = req_obj.at("misc").as_object();

                const auto& cpu = req_obj.at("cpu").as_object();
                const auto& mem = req_obj.at("mem").as_object();

                const auto cpu_slots = json_int_field(cpu, "slots", 1);
                const auto mem_mib = json_int_field(mem, "capacity", 1024);
                const auto os_family = json_string_field(misc, "os_family", "linux");
                const auto os_flavour = json_string_field(misc, "os_flavour", "ubuntu");
                if (os_family.empty() || os_flavour.empty())
                    throw std::runtime_error(
                        "request was badly formatted. 'req.misc.os_family/os_flavour'");

                std::int64_t disk_gb = 5;
                if (!volumes.empty() && volumes.front().is_object())
                    disk_gb = json_int_field(volumes.front().as_object(), "size", 5);

                LaunchSpec spec;
                spec.instance_name = vm_name;
                spec.image = image_for_flavour(os_flavour);
                spec.num_cores = static_cast<int>(std::max<std::int64_t>(cpu_slots, 1));
                spec.mem_size = fmt::format("{}M", std::max<std::int64_t>(mem_mib, 512));
                spec.disk_space = fmt::format("{}G", std::max<std::int64_t>(disk_gb, 1));
                spec.cloud_init_user_data = build_cloud_init(body);

                mpl::log(mpl::Level::debug,
                         service_category,
                         "launching '{}' image='{}' cores={} mem={} disk={} client_uid={}",
                         spec.instance_name,
                         spec.image,
                         spec.num_cores,
                         spec.mem_size,
                         spec.disk_space,
                         client_uid);

                const auto result = hyperpass_backend.launch(spec);
                if (!result.status.ok())
                {
                    mpl::log(mpl::Level::warning,
                             service_category,
                             "launch failed for '{}': {}",
                             vm_name,
                             result.status.error_message());
                    set_daemon_error(res, result.status);
                    return;
                }

                RegisteredVm record;
                record.vm_uid = mp::utils::make_uuid();
                record.vm_name = vm_name;
                record.client_uid = client_uid;
                record.os_family = os_family;
                record.os_flavour = os_flavour;
                record.backend = backend_name;

                std::string guest_ip;
                json::array ipv4;
                const auto listed = hyperpass_backend.list_instances(true);
                if (listed.status.ok() && listed.reply.has_instance_list())
                {
                    for (const auto& inst : listed.reply.instance_list().instances())
                    {
                        if (inst.name() == vm_name)
                        {
                            for (const auto& ip : inst.ipv4())
                            {
                                ipv4.emplace_back(ip);
                                if (guest_ip.empty())
                                    guest_ip = ip;
                            }
                            break;
                        }
                    }
                }

                const auto safe_req = build_electros_req_json(req_obj,
                                                              vm_name,
                                                              os_family,
                                                              os_flavour,
                                                              volumes,
                                                              networks,
                                                              autostart,
                                                              "running",
                                                              guest_ip);
                record.req_json = json::serialize(safe_req);
                record.xml = fmt::format(
                    "<domain type='hyperpass'><name>{}</name><uuid>{}</uuid></domain>",
                    record.vm_name,
                    record.vm_uid);
                registry.upsert(record);

                mpl::log(mpl::Level::info,
                         service_category,
                         "registered '{}' as vm_uid={} for client_uid={}",
                         vm_name,
                         record.vm_uid,
                         client_uid);

                json::array ipv4_after;
                if (ipv4.empty())
                {
                    const auto listed_after = hyperpass_backend.list_instances(true);
                    if (listed_after.status.ok() && listed_after.reply.has_instance_list())
                    {
                        for (const auto& inst : listed_after.reply.instance_list().instances())
                        {
                            if (inst.name() == vm_name)
                            {
                                for (const auto& ip : inst.ipv4())
                                    ipv4_after.emplace_back(ip);
                                break;
                            }
                        }
                    }
                }
                else
                {
                    ipv4_after = std::move(ipv4);
                }

                json::object out;
                out["registered"] = true;
                // Matcher / Electros fields (required by matcher-client.registerSpec / running).
                out["uniqueID"] = record.vm_uid;
                out["req_json"] = safe_req;
                out["xml"] = record.xml;
                out["is_gateway"] = false;
                // Service / Meson fields (Bruno service collection).
                out["vm_uid"] = record.vm_uid;
                out["vm_name"] = record.vm_name;
                out["state"] = "running";
                out["ipv4"] = std::move(ipv4_after);
                out["backend"] = backend_name;
                set_json(res, 200, out);
            }
            catch (const std::exception& e)
            {
                json::object err;
                err["error"] = e.what();
                set_json(res, 400, err);
            }
        };
    server.Post("/api/v1.0/register", register_or_create);
    server.Post("/api/v1.0/create_machine", register_or_create);

    const httplib::Server::Handler running_or_get =
        [&hyperpass_backend, &registry](const httplib::Request& req, httplib::Response& res) {
            const auto body_opt = parse_object_body(req, res);
            if (!body_opt)
                return;
            const auto client_uid = json_string_field(*body_opt, "client_uid");
            if (client_uid.empty())
            {
                set_json(res,
                         400,
                         json::object{{"error", "request was badly formatted. 'client_uid'"}});
                return;
            }

            const auto listed = hyperpass_backend.list_instances(true);
            if (!listed.status.ok())
            {
                set_daemon_error(res, listed.status);
                return;
            }

            std::unordered_map<std::string, const mp::ListVMInstance*> by_name;
            if (listed.reply.has_instance_list())
            {
                for (const auto& inst : listed.reply.instance_list().instances())
                    by_name.emplace(inst.name(), &inst);
            }

            json::array vms;
            for (const auto& recorded : registry.list_for_client(client_uid))
            {
                const auto it = by_name.find(recorded.vm_name);
                if (it == by_name.end())
                    continue;

                std::string guest_ip;
                for (const auto& ip : it->second->ipv4())
                {
                    if (guest_ip.empty())
                        guest_ip = ip;
                }

                json::object item;
                // Matcher / Electros shape (retrieveRunningSpecs reads response.json()['vms']).
                item["uniqueID"] = recorded.vm_uid;
                item["req_json"] =
                    synthesize_req_json(recorded, instance_status_name(it->second->instance_status()), guest_ip);
                item["xml"] = domain_xml_for(recorded);
                item["is_gateway"] = false;
                item["external"] = false;
                // Service / Bruno extras (harmless for matcher).
                item["vm_uid"] = recorded.vm_uid;
                item["vm_name"] = recorded.vm_name;
                item["state"] = instance_status_name(it->second->instance_status());
                json::array ipv4;
                for (const auto& ip : it->second->ipv4())
                    ipv4.emplace_back(ip);
                item["ipv4"] = std::move(ipv4);
                item["os_family"] = recorded.os_family;
                item["os_flavour"] = recorded.os_flavour;
                item["client_uid"] = recorded.client_uid;
                item["backend"] = recorded.backend;
                vms.push_back(std::move(item));
            }

            json::object out;
            out["vms"] = std::move(vms);
            set_json(res, 200, out);
        };
    server.Get("/api/v1.0/running", running_or_get);
    server.Get("/api/v1.0/get_machine", running_or_get);

    auto resolve_vm_uid = [](const json::object& body) {
        // Electros matcher uses uniqueID; Service/Bruno use vm_uid.
        auto id = json_string_field(body, "vm_uid");
        if (id.empty())
            id = json_string_field(body, "uniqueID");
        return id;
    };

    const httplib::Server::Handler unregister_or_delete =
        [&hyperpass_backend, &registry, resolve_vm_uid](const httplib::Request& req,
                                                        httplib::Response& res) {
            const auto body_opt = parse_object_body(req, res);
            if (!body_opt)
                return;
            const auto& body = *body_opt;
            const auto vm_uid = resolve_vm_uid(body);
            const auto client_uid = json_string_field(body, "client_uid");
            if (vm_uid.empty() || client_uid.empty())
            {
                set_json(res,
                         400,
                         json::object{
                             {"error",
                              "request was badly formatted. 'vm_uid'|'uniqueID'/'client_uid'"}});
                return;
            }

            const auto record = registry.find_by_uid(vm_uid);
            if (!record || record->client_uid != client_uid)
            {
                set_json(res, 404, json::object{{"error", "not_found"}});
                return;
            }

            bool purge = false;
            if (body.contains("purge"))
                purge = json_truthy(body.at("purge"));

            const auto result = hyperpass_backend.delete_instance(record->vm_name, purge);
            if (!result.status.ok())
            {
                set_daemon_error(res, result.status);
                return;
            }

            registry.remove(vm_uid);
            json::object out;
            out["unregistered"] = true;
            out["vm_uid"] = vm_uid;
            out["uniqueID"] = vm_uid;
            out["purged"] = purge;
            set_json(res, 200, out);
        };
    server.Delete("/api/v1.0/unregister", unregister_or_delete);
    server.Delete("/api/v1.0/delete_machine", unregister_or_delete);
    // Electros historically POSTed unregister in some code paths.
    server.Post("/api/v1.0/unregister", unregister_or_delete);

    auto require_registered =
        [&registry, resolve_vm_uid](const json::object& body,
                                    httplib::Response& res) -> std::optional<RegisteredVm> {
        const auto vm_uid = resolve_vm_uid(body);
        const auto client_uid = json_string_field(body, "client_uid");
        if (vm_uid.empty() || client_uid.empty())
        {
            set_json(res,
                     400,
                     json::object{
                         {"error",
                          "request was badly formatted. 'vm_uid'|'uniqueID'/'client_uid'"}});
            return std::nullopt;
        }
        const auto record = registry.find_by_uid(vm_uid);
        if (!record || record->client_uid != client_uid)
        {
            set_json(res, 404, json::object{{"error", "not_found"}});
            return std::nullopt;
        }
        return record;
    };

    server.Post("/api/v1.0/start",
                [&hyperpass_backend, require_registered](const httplib::Request& req,
                                                         httplib::Response& res) {
                    const auto body_opt = parse_object_body(req, res);
                    if (!body_opt)
                        return;
                    const auto record = require_registered(*body_opt, res);
                    if (!record)
                        return;

                    const auto listed = hyperpass_backend.list_instances(false);
                    if (listed.status.ok() && listed.reply.has_instance_list())
                    {
                        for (const auto& inst : listed.reply.instance_list().instances())
                        {
                            if (inst.name() == record->vm_name &&
                                instance_status_name(inst.instance_status()) == "running")
                            {
                                set_json(res, 409, json::object{{"error", "VM is already running"}});
                                return;
                            }
                        }
                    }

                    const auto result = hyperpass_backend.start(record->vm_name);
                    if (!result.status.ok())
                    {
                        set_daemon_error(res, result.status);
                        return;
                    }
                    res.status = 200;
                    res.set_content("OK", "text/plain");
                });

    server.Post("/api/v1.0/stop",
                [&hyperpass_backend, require_registered](const httplib::Request& req,
                                                         httplib::Response& res) {
                    const auto body_opt = parse_object_body(req, res);
                    if (!body_opt)
                        return;
                    const auto record = require_registered(*body_opt, res);
                    if (!record)
                        return;

                    const auto result = hyperpass_backend.stop(record->vm_name);
                    if (!result.status.ok())
                    {
                        set_daemon_error(res, result.status);
                        return;
                    }
                    res.status = 200;
                    res.set_content("OK", "text/plain");
                });

    server.Post("/api/v1.0/reboot",
                [&hyperpass_backend, require_registered](const httplib::Request& req,
                                                         httplib::Response& res) {
                    const auto body_opt = parse_object_body(req, res);
                    if (!body_opt)
                        return;
                    const auto record = require_registered(*body_opt, res);
                    if (!record)
                        return;

                    const auto result = hyperpass_backend.restart(record->vm_name);
                    if (!result.status.ok())
                    {
                        set_daemon_error(res, result.status);
                        return;
                    }
                    res.status = 200;
                    res.set_content("OK", "text/plain");
                });

    server.Get("/api/v1.0/images/find",
               [&hyperpass_backend](const httplib::Request& req, httplib::Response& res) {
                   const auto query = req.get_param_value("query");
                   const auto remote = req.get_param_value("remote");
                   const auto result = hyperpass_backend.find(query, remote);
                   if (!result.status.ok())
                   {
                       set_daemon_error(res, result.status);
                       return;
                   }

                   json::array images;
                   for (const auto& info : result.reply.images_info())
                   {
                       json::object item;
                       item["os"] = info.os();
                       item["release"] = info.release();
                       item["version"] = info.version();
                       json::array aliases;
                       for (const auto& alias : info.aliases())
                           aliases.emplace_back(alias);
                       item["aliases"] = std::move(aliases);
                       item["codename"] = info.codename();
                       item["remote"] = info.remote_name();
                       item["os_family"] = "linux";
                       item["os_flavour"] = flavour_from_os(info.os(), info.codename());
                       item["min_disk"] = info.min_disk();
                       images.push_back(std::move(item));
                   }

                   set_json(res, 200, json::object{{"images", std::move(images)}});
               });
}

std::int64_t mp::api::requested_mib_from_canallocate_body(std::string_view body)
{
    return parse_requested_mib(body);
}
