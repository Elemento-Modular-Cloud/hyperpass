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

#include "handlers.h"

#include <boost/json.hpp>

#include <multipass/constants.h>
#include <multipass/format.h>

namespace mp = multipass;
namespace json = boost::json;

namespace
{
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

std::string daemon_status_name(bool reachable)
{
    return reachable ? "ready" : "not_ready";
}
} // namespace

void mp::api::register_health_handlers(httplib::Server& server,
                                       GrpcBackend& elp_backend,
                                       GrpcBackend* multipass_backend)
{
    server.Get("/healthz", [](const httplib::Request&, httplib::Response& res) {
        json::object body;
        body["status"] = "ok";
        res.set_content(json::serialize(body), "application/json");
    });

    server.Get("/readyz",
               [&elp_backend, multipass_backend](const httplib::Request&,
                                                       httplib::Response& res) {
                   const bool hp_ok = elp_backend.ping();
                   json::object body;
                   body["elp"] = daemon_status_name(hp_ok);
                   if (multipass_backend)
                       body["multipass"] = daemon_status_name(multipass_backend->ping());
                   else
                       body["multipass"] = "unavailable";

                   if (hp_ok)
                   {
                       body["status"] = "ready";
                       res.status = 200;
                   }
                   else
                   {
                       body["status"] = "not_ready";
                       body["message"] = "elpd gRPC unreachable";
                       res.status = 503;
                   }
                   res.set_content(json::serialize(body), "application/json");
               });
}

void mp::api::append_instances_from_reply(json::array& out,
                                          const ListReply& reply,
                                          std::string_view source)
{
    if (!reply.has_instance_list())
        return;

    for (const auto& instance : reply.instance_list().instances())
    {
        json::object item;
        item["name"] = instance.name();
        item["source"] = source;
        item["state"] = instance_status_name(instance.instance_status());
        item["release"] = instance.current_release();
        if (!instance.os().empty())
            item["os"] = instance.os();

        json::array ipv4;
        for (const auto& ip : instance.ipv4())
            ipv4.emplace_back(ip);
        item["ipv4"] = std::move(ipv4);

        if (instance.has_zone() && !instance.zone().name().empty())
            item["zone"] = instance.zone().name();

        out.push_back(std::move(item));
    }
}

std::string mp::api::list_reply_to_json(const ListReply& reply, std::string_view source)
{
    json::object root;
    json::array instances;
    append_instances_from_reply(instances, reply, source);
    root["instances"] = std::move(instances);
    return json::serialize(root);
}

void mp::api::register_instance_handlers(httplib::Server& server,
                                         GrpcBackend& elp_backend,
                                         GrpcBackend* multipass_backend)
{
    server.Get("/v1/instances",
               [&elp_backend, multipass_backend](const httplib::Request& req,
                                                       httplib::Response& res) {
                   const bool request_ipv4 = req.get_param_value("ipv4") != "false";
                   const auto source_filter = req.get_param_value("source");
                   const bool want_elp =
                       source_filter.empty() || source_filter == mp::instance_source_elp;
                   const bool want_multipass =
                       source_filter.empty() || source_filter == mp::instance_source_multipass;

                   if (!source_filter.empty() && !want_elp && !want_multipass)
                   {
                       json::object body;
                       body["error"] = "invalid_parameter";
                       body["message"] = "source must be 'elp' or 'multipass'";
                       res.status = 400;
                       res.set_content(json::serialize(body), "application/json");
                       return;
                   }

                   if (want_multipass && !multipass_backend &&
                       source_filter == mp::instance_source_multipass)
                   {
                       json::object body;
                       body["error"] = "unavailable";
                       body["message"] = "Multipass daemon not discovered";
                       res.status = 503;
                       res.set_content(json::serialize(body), "application/json");
                       return;
                   }

                   json::array instances;
                   json::array errors;
                   bool any_success = false;

                   if (want_elp)
                   {
                       const auto result = elp_backend.list_instances(request_ipv4);
                       if (result.status.ok())
                       {
                           append_instances_from_reply(instances,
                                                       result.reply,
                                                       mp::instance_source_elp);
                           any_success = true;
                       }
                       else
                       {
                           json::object err;
                           err["source"] = mp::instance_source_elp;
                           err["message"] = result.status.error_message();
                           err["code"] = static_cast<std::int64_t>(result.status.error_code());
                           errors.push_back(std::move(err));
                       }
                   }

                   if (want_multipass && multipass_backend)
                   {
                       const auto result = multipass_backend->list_instances(request_ipv4);
                       if (result.status.ok())
                       {
                           append_instances_from_reply(instances,
                                                       result.reply,
                                                       mp::instance_source_multipass);
                           any_success = true;
                       }
                       else
                       {
                           json::object err;
                           err["source"] = mp::instance_source_multipass;
                           err["message"] = result.status.error_message();
                           err["code"] = static_cast<std::int64_t>(result.status.error_code());
                           errors.push_back(std::move(err));
                       }
                   }

                   if (!any_success)
                   {
                       json::object body;
                       body["error"] = "daemon_error";
                       body["message"] = "failed to list instances from requested daemon(s)";
                       body["errors"] = std::move(errors);
                       res.status = 502;
                       res.set_content(json::serialize(body), "application/json");
                       return;
                   }

                   json::object root;
                   root["instances"] = std::move(instances);
                   if (!errors.empty())
                       root["errors"] = std::move(errors);
                   res.status = 200;
                   res.set_content(json::serialize(root), "application/json");
               });
}

std::string mp::api::operation_to_json(const Operation& op)
{
    json::object body;
    body["id"] = op.id;
    body["kind"] = op.kind;
    body["state"] = operation_state_name(op.state);
    if (!op.message.empty())
        body["message"] = op.message;
    if (!op.error.empty())
        body["error"] = op.error;
    return json::serialize(body);
}

void mp::api::register_operation_handlers(httplib::Server& server, OperationTracker& tracker)
{
    server.Get(R"(/v1/operations/([^/]+))",
               [&tracker](const httplib::Request& req, httplib::Response& res) {
                   const auto id = req.matches[1].str();
                   const auto op = tracker.get(id);
                   if (!op)
                   {
                       json::object body;
                       body["error"] = "not_found";
                       body["message"] = fmt::format("operation '{}' not found", id);
                       res.status = 404;
                       res.set_content(json::serialize(body), "application/json");
                       return;
                   }

                   res.status = 200;
                   res.set_content(operation_to_json(*op), "application/json");
               });
}
