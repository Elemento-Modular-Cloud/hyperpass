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

#include "marketplace_cloud_init.h"
#include "spot_spec.h"

#include <boost/json.hpp>

#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/utils.h>
#include <multipass/version.h>
#include <multipass/constants.h>

#include <algorithm>
#include <optional>
#include <stdexcept>
#include <string>

namespace mpl = multipass::logging;

namespace mp = multipass;
namespace json = boost::json;

namespace
{
constexpr auto service_category = "api-service";

std::string json_string_field(const json::object& obj, std::string_view key, std::string_view fallback = {})
{
    if (!obj.contains(key) || !obj.at(key).is_string())
        return std::string{fallback};
    return std::string(obj.at(key).as_string());
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
        body["error"] = "elp backend unreachable";
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
    if (status.error_code() == grpc::StatusCode::RESOURCE_EXHAUSTED)
    {
        json::object body;
        body["error"] = "insufficient_resources";
        body["message"] = status.error_message();
        set_json(res, 507, body);
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

std::optional<json::object> parse_object_body(const httplib::Request& req, httplib::Response& res)
{
    if (req.body.empty())
    {
        json::object body;
        body["error"] = "request was badly formatted. missing body";
        set_json(res, 400, body);
        return std::nullopt;
    }

    try
    {
        const auto parsed = json::parse(req.body);
        if (!parsed.is_object())
        {
            json::object body;
            body["error"] = "request was badly formatted. body must be a JSON object";
            set_json(res, 400, body);
            return std::nullopt;
        }
        return parsed.as_object();
    }
    catch (const std::exception& e)
    {
        json::object body;
        body["error"] = fmt::format("request was badly formatted. {}", e.what());
        set_json(res, 400, body);
        return std::nullopt;
    }
}

std::string header_or(const httplib::Request& req, const char* name, std::string_view fallback)
{
    const auto value = req.get_header_value(name);
    return value.empty() ? std::string{fallback} : value;
}

std::string resolve_user_data(const mp::api::SpotSpec& spec, std::string_view gateway_ca_pem)
{
    std::string user_data;
    if (!spec.startup_template.empty())
    {
        const auto library = mp::api::load_marketplace_library();
        const auto* service = library.lookup(spec.startup_template);
        if (!service)
            throw std::runtime_error(
                fmt::format("unknown marketplace template '{}'", spec.startup_template));
        user_data = mp::api::render_marketplace_cloud_init(*service, gateway_ca_pem);
    }
    else if (spec.has_cloud_init_b64)
        user_data = mp::api::decode_cloud_init_b64(spec.cloud_init_b64);

    return mp::api::merge_auth_into_cloud_init(std::move(user_data), spec.auth);
}

bool daemon_can_place(mp::api::GrpcBackend& backend, const mp::api::SpotSpec& spec, httplib::Response& res)
{
    if (!backend.ping())
    {
        set_json(res, 503, json::object{{"error", "elp backend unreachable"}, {"canallocate", false}});
        return false;
    }
    const auto info = backend.daemon_info();
    if (!info.status.ok())
    {
        set_json(res, 503, json::object{{"error", info.status.error_message()}, {"canallocate", false}});
        return false;
    }
    const auto available_mib =
        static_cast<std::int64_t>(info.reply.memory_available() / (1024 * 1024));
    const auto available_slots = std::max<std::int64_t>(
        0,
        static_cast<std::int64_t>(info.reply.cpus()) - info.reply.cpus_claimed());
    return mp::api::can_place_spot(spec, available_mib, available_slots);
}

std::int64_t credential_port(const mp::api::RegisteredVm& recorded, const mp::api::SpotSpec& spec)
{
    const auto from_spec = mp::api::first_open_port(spec);
    if (from_spec > 0)
        return from_spec;
    if (recorded.template_id.empty() && recorded.service_id.empty())
        return 0;
    try
    {
        const auto library = mp::api::load_marketplace_library();
        const auto handle = recorded.template_id.empty() ? recorded.service_id : recorded.template_id;
        if (const auto* service = library.lookup(handle))
            return mp::api::first_marketplace_ingress_port(*service);
    }
    catch (const std::exception&)
    {
    }
    return 0;
}

json::object running_item_from(const mp::api::RegisteredVm& recorded, const mp::ListVMInstance& inst)
{
    json::object item;
    if (!recorded.spec_json.empty())
    {
        try
        {
            const auto parsed = json::parse(recorded.spec_json);
            if (parsed.is_object())
                item = parsed.as_object();
        }
        catch (const std::exception&)
        {
        }
    }
    item["vm_uid"] = recorded.vm_uid;
    item["vm_name"] = recorded.vm_name;
    item["status"] = instance_status_name(inst.instance_status());
    item["region"] = recorded.region.empty() ? "local" : recorded.region;
    if (!item.contains("tags") || !item.at("tags").is_array())
        item["tags"] = json::array{};

    json::array networks;
    if (item.contains("networks") && item.at("networks").is_array())
        networks = item.at("networks").as_array();
    if (networks.empty())
        networks.push_back(json::object{{"kind", "natted"}});
    if (!networks.empty() && networks.front().is_object())
    {
        auto net = networks.front().as_object();
        if (inst.ipv4_size() > 0)
            net["ipv4"] = inst.ipv4(0);
        else
            net["ipv4"] = nullptr;
        networks[0] = std::move(net);
    }
    item["networks"] = std::move(networks);
    return item;
}

grpc::Status append_running_from(mp::api::GrpcBackend& backend,
                                 std::string_view source,
                                 mp::api::VmRegistry& registry,
                                 json::array& out)
{
    const auto listed = backend.list_instances(true);
    if (!listed.status.ok())
        return listed.status;
    if (!listed.reply.has_instance_list())
        return grpc::Status::OK;

    const auto src = std::string{source};
    for (const auto& inst : listed.reply.instance_list().instances())
    {
        auto existing = registry.find_by_name(inst.name(), src);
        mp::api::RegisteredVm record;
        if (existing)
            record = std::move(*existing);
        else
        {
            record.vm_uid = mp::utils::make_uuid();
            record.vm_name = inst.name();
            record.source = src;
            record.region = "local";
            record.service_id = inst.service_id();
            record.template_id = inst.service_id();
            const auto spec = mp::api::spec_from_daemon_fields(inst.name(),
                                                               inst.current_release(),
                                                               inst.os(),
                                                               inst.service_id());
            record.spec_json = json::serialize(mp::api::spec_to_public_json(spec));
            registry.upsert(record);
        }
        out.push_back(running_item_from(record, inst));
    }
    return grpc::Status::OK;
}

mp::api::GrpcBackend* backend_for_record(const mp::api::RegisteredVm& record,
                                         mp::api::GrpcBackend& elp_backend,
                                         mp::api::GrpcBackend* multipass_backend)
{
    if (mp::api::normalize_vm_source(record.source) == mp::instance_source_multipass)
        return multipass_backend;
    return &elp_backend;
}
} // namespace

void mp::api::register_service_handlers(httplib::Server& server,
                                        GrpcBackend& elp_backend,
                                        VmRegistry& registry,
                                        std::string_view gateway_ca_pem,
                                        GrpcBackend* multipass_backend)
{
    const std::string ca_pem{gateway_ca_pem};

    server.Get("/", [&elp_backend](const httplib::Request&, httplib::Response& res) {
        if (!elp_backend.ping())
        {
            set_json(res, 503, json::object{{"error", "elp backend unreachable"}});
            return;
        }
        res.status = 200;
        res.set_content("OK", "text/plain");
    });

    server.Get("/version", [&elp_backend](const httplib::Request&, httplib::Response& res) {
        json::object body;
        body["version"] = multipass::version_string;
        body["backend"] = "elp";

        const auto ver = elp_backend.version();
        if (ver.status.ok())
            body["backend_version"] = ver.reply.version();
        else
            body["backend_version"] = multipass::version_string;

        set_json(res, 200, body);
    });

    const httplib::Server::Handler canallocate_handler =
        [&elp_backend](const httplib::Request& req, httplib::Response& res) {
            mpl::log(mpl::Level::debug,
                     service_category,
                     "canallocate from {} ({} bytes)",
                     req.remote_addr,
                     req.body.size());
            try
            {
                const auto spec = parse_spot_spec(req.body, SpotParseMode::canallocate);
                const bool can = daemon_can_place(elp_backend, spec, res);
                if (res.status == 503)
                    return;
                set_json(res, 200, json::object{{"canallocate", can}});
            }
            catch (const std::exception& e)
            {
                set_json(res, 400, json::object{{"error", e.what()}});
            }
        };
    server.Get("/api/v1.0/canallocate", canallocate_handler);
    server.Post("/api/v1.0/canallocate", canallocate_handler);

    server.Post("/api/v1.0/register",
                [&elp_backend, &registry, ca_pem](const httplib::Request& req, httplib::Response& res) {
                    const auto body_opt = parse_object_body(req, res);
                    if (!body_opt)
                        return;
                    try
                    {
                        auto spec = parse_spot_spec(*body_opt, SpotParseMode::register_vm);
                        spec.region = header_or(req, "X-Region", "local");

                        if (!daemon_can_place(elp_backend, spec, res))
                        {
                            if (res.status == 503)
                                return;
                            json::object body;
                            body["error"] = "insufficient_resources";
                            body["canallocate"] = false;
                            set_json(res, 507, body);
                            return;
                        }

                        auto user_data = resolve_user_data(spec, ca_pem);
                        auto launch = launch_spec_from_spot(spec, std::move(user_data));

                        mpl::log(mpl::Level::debug,
                                 service_category,
                                 "launching '{}' image='{}' cores={} mem={} disk={} template='{}'",
                                 launch.instance_name,
                                 launch.image,
                                 launch.num_cores,
                                 launch.mem_size,
                                 launch.disk_space,
                                 spec.startup_template);

                        const auto result = elp_backend.launch(launch);
                        if (!result.status.ok())
                        {
                            mpl::log(mpl::Level::warning,
                                     service_category,
                                     "launch failed for '{}': {}",
                                     spec.vm_name,
                                     result.status.error_message());
                            set_daemon_error(res, result.status);
                            return;
                        }

                        RegisteredVm record;
                        record.vm_uid = mp::utils::make_uuid();
                        record.vm_name = spec.vm_name;
                        record.username = spec.auth.username;
                        record.region = spec.region;
                        record.template_id = spec.startup_template;
                        record.service_id = service_id_from_spec(spec);
                        record.spec_json = json::serialize(spec_to_public_json(spec));
                        record.source = mp::instance_source_elp;
                        registry.upsert(record);

                        json::object out;
                        out["vm_uid"] = record.vm_uid;
                        out["vm_name"] = record.vm_name;
                        out["status"] = "running";
                        set_json(res, 200, out);
                    }
                    catch (const std::exception& e)
                    {
                        set_json(res, 400, json::object{{"error", e.what()}});
                    }
                });

    server.Get("/api/v1.0/running",
               [&elp_backend, multipass_backend, &registry](const httplib::Request&,
                                                            httplib::Response& res) {
                   json::array out;
                   const auto elp_status =
                       append_running_from(elp_backend, mp::instance_source_elp, registry, out);
                   grpc::Status mp_status = grpc::Status::OK;
                   if (multipass_backend)
                   {
                       mp_status = append_running_from(*multipass_backend,
                                                       mp::instance_source_multipass,
                                                       registry,
                                                       out);
                   }

                   if (!elp_status.ok() && (!multipass_backend || !mp_status.ok()))
                   {
                       set_daemon_error(res, elp_status);
                       return;
                   }

                   res.status = 200;
                   res.set_content(json::serialize(out), "application/json");
               });

    server.Get(R"(/api/v1.0/credentials/([^/]+))",
               [&elp_backend, multipass_backend, &registry](const httplib::Request& req,
                                                            httplib::Response& res) {
                   const auto vm_uid = req.matches[1].str();
                   const auto record = registry.find_by_uid(vm_uid);
                   if (!record)
                   {
                       set_json(res, 500, json::object{{"error", fmt::format("VM {} not found", vm_uid)}});
                       return;
                   }

                   auto* backend = backend_for_record(*record, elp_backend, multipass_backend);
                   if (!backend)
                   {
                       set_json(res,
                                503,
                                json::object{{"error", "multipass backend unavailable"},
                                             {"vm_uid", record->vm_uid}});
                       return;
                   }

                   json::object out;
                   out["vm_uid"] = record->vm_uid;
                   out["state"] = "Succeeded";

                   const auto ssh = backend->ssh_info(record->vm_name);
                   if (ssh.status.ok())
                   {
                       const auto& map = ssh.reply.ssh_info();
                       const auto it = map.find(record->vm_name);
                       if (it != map.end())
                       {
                           out["username"] = it->second.username();
                           out["ssh_host"] = it->second.host();
                           out["ssh_port"] = it->second.port();
                           out["state"] = "Succeeded";
                       }
                   }
                   if (!out.contains("username"))
                   {
                       if (!record->username.empty())
                           out["username"] = record->username;
                       const auto listed = backend->list_instances(true);
                       if (listed.status.ok() && listed.reply.has_instance_list())
                       {
                           for (const auto& inst : listed.reply.instance_list().instances())
                           {
                               if (inst.name() == record->vm_name && inst.ipv4_size() > 0)
                               {
                                   out["ssh_host"] = inst.ipv4(0);
                                   out["ssh_port"] = 22;
                                   break;
                               }
                           }
                       }
                   }

                   SpotSpec spec;
                   try
                   {
                       if (!record->spec_json.empty())
                           spec = parse_spot_spec(record->spec_json, SpotParseMode::canallocate);
                   }
                   catch (const std::exception&)
                   {
                   }
                   spec.startup_template = record->template_id;
                   spec.vm_name = record->vm_name;

                   const auto template_id =
                       record->template_id.empty() ? record->service_id : record->template_id;
                   if (!template_id.empty())
                   {
                       out["template"] = template_id;
                       const auto host = json_string_field(out, "ssh_host");
                       const auto port = credential_port(*record, spec);
                       if (!host.empty() && port > 0)
                           out["url"] = fmt::format("http://{}:{}", host, port);
                   }

                   set_json(res, 200, out);
               });

    server.Delete("/api/v1.0/unregister",
                  [&elp_backend, multipass_backend, &registry](const httplib::Request& req,
                                                               httplib::Response& res) {
                      const auto body_opt = parse_object_body(req, res);
                      if (!body_opt)
                          return;
                      const auto vm_uid = json_string_field(*body_opt, "vm_uid");
                      if (vm_uid.empty())
                      {
                          set_json(res, 400, json::object{{"error", "request was badly formatted. 'vm_uid'"}});
                          return;
                      }
                      const auto record = registry.find_by_uid(vm_uid);
                      if (!record)
                      {
                          set_json(res, 404, json::object{{"error", "VM not found"}});
                          return;
                      }
                      auto* backend = backend_for_record(*record, elp_backend, multipass_backend);
                      if (!backend)
                      {
                          set_json(res,
                                   503,
                                   json::object{{"error", "multipass backend unavailable"},
                                                {"vm_uid", vm_uid}});
                          return;
                      }
                      const auto result = backend->delete_instance(record->vm_name, true);
                      if (!result.status.ok() && result.status.error_code() != grpc::StatusCode::NOT_FOUND)
                      {
                          set_daemon_error(res, result.status);
                          return;
                      }
                      registry.remove(vm_uid);
                      json::object out;
                      out["vm_uid"] = vm_uid;
                      out["status"] = "deleted";
                      set_json(res, 200, out);
                  });
}
