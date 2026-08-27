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

#include <boost/json.hpp>

#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/utils.h>
#include <multipass/version.h>

#include <algorithm>
#include <cctype>
#include <optional>
#include <string>
#include <unordered_map>

namespace mp = multipass;
namespace json = boost::json;

namespace
{
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
                const auto vm_name = json_string_field(body, "vm_name");
                const auto client_uid = json_string_field(body, "client_uid");
                if (vm_name.empty())
                    throw std::runtime_error("request was badly formatted. 'vm_name'");
                if (client_uid.empty())
                    throw std::runtime_error("request was badly formatted. 'client_uid'");
                if (!body.contains("req") || !body.at("req").is_object())
                    throw std::runtime_error("request was badly formatted. 'req'");
                if (!body.contains("volumes") || !body.at("volumes").is_array() ||
                    body.at("volumes").as_array().empty())
                    throw std::runtime_error("request was badly formatted. 'volumes'");

                const auto& req_obj = body.at("req").as_object();
                if (!req_obj.contains("cpu") || !req_obj.at("cpu").is_object())
                    throw std::runtime_error("request was badly formatted. 'req.cpu'");
                if (!req_obj.contains("mem") || !req_obj.at("mem").is_object())
                    throw std::runtime_error("request was badly formatted. 'req.mem'");
                if (!req_obj.contains("misc") || !req_obj.at("misc").is_object())
                    throw std::runtime_error("request was badly formatted. 'req.misc'");

                const auto& cpu = req_obj.at("cpu").as_object();
                const auto& mem = req_obj.at("mem").as_object();
                const auto& misc = req_obj.at("misc").as_object();

                const auto cpu_slots = json_int_field(cpu, "slots", 1);
                const auto mem_mib = json_int_field(mem, "capacity", 1024);
                const auto os_family = json_string_field(misc, "os_family", "linux");
                const auto os_flavour = json_string_field(misc, "os_flavour", "ubuntu");
                if (os_family.empty() || os_flavour.empty())
                    throw std::runtime_error(
                        "request was badly formatted. 'req.misc.os_family/os_flavour'");

                const auto& volumes = body.at("volumes").as_array();
                const auto disk_gb = json_int_field(volumes.front().as_object(), "size", 5);

                LaunchSpec spec;
                spec.instance_name = vm_name;
                spec.image = image_for_flavour(os_flavour);
                spec.num_cores = static_cast<int>(std::max<std::int64_t>(cpu_slots, 1));
                spec.mem_size = fmt::format("{}M", std::max<std::int64_t>(mem_mib, 512));
                spec.disk_space = fmt::format("{}G", std::max<std::int64_t>(disk_gb, 1));
                spec.cloud_init_user_data = build_cloud_init(body);

                const auto result = hyperpass_backend.launch(spec);
                if (!result.status.ok())
                {
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
                registry.upsert(record);

                json::array ipv4;
                const auto listed = hyperpass_backend.list_instances(true);
                if (listed.status.ok() && listed.reply.has_instance_list())
                {
                    for (const auto& inst : listed.reply.instance_list().instances())
                    {
                        if (inst.name() == vm_name)
                        {
                            for (const auto& ip : inst.ipv4())
                                ipv4.emplace_back(ip);
                            break;
                        }
                    }
                }

                json::object out;
                out["registered"] = true;
                out["vm_uid"] = record.vm_uid;
                out["vm_name"] = record.vm_name;
                out["state"] = "running";
                out["ipv4"] = std::move(ipv4);
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

            json::array out;
            for (const auto& recorded : registry.list_for_client(client_uid))
            {
                const auto it = by_name.find(recorded.vm_name);
                if (it == by_name.end())
                    continue;

                json::object item;
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
                out.push_back(std::move(item));
            }

            set_json(res, 200, out);
        };
    server.Get("/api/v1.0/running", running_or_get);
    server.Get("/api/v1.0/get_machine", running_or_get);

    const httplib::Server::Handler unregister_or_delete =
        [&hyperpass_backend, &registry](const httplib::Request& req, httplib::Response& res) {
            const auto body_opt = parse_object_body(req, res);
            if (!body_opt)
                return;
            const auto& body = *body_opt;
            const auto vm_uid = json_string_field(body, "vm_uid");
            const auto client_uid = json_string_field(body, "client_uid");
            if (vm_uid.empty() || client_uid.empty())
            {
                set_json(
                    res,
                    400,
                    json::object{{"error", "request was badly formatted. 'vm_uid'/'client_uid'"}});
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
            out["purged"] = purge;
            set_json(res, 200, out);
        };
    server.Delete("/api/v1.0/unregister", unregister_or_delete);
    server.Delete("/api/v1.0/delete_machine", unregister_or_delete);
    auto require_registered =
        [&registry](const json::object& body, httplib::Response& res) -> std::optional<RegisteredVm> {
        const auto vm_uid = json_string_field(body, "vm_uid");
        const auto client_uid = json_string_field(body, "client_uid");
        if (vm_uid.empty() || client_uid.empty())
        {
            set_json(
                res,
                400,
                json::object{{"error", "request was badly formatted. 'vm_uid'/'client_uid'"}});
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
