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
#include <multipass/format.h>
#include <multipass/logging/log.h>

#ifndef CPPHTTPLIB_OPENSSL_SUPPORT
#define CPPHTTPLIB_OPENSSL_SUPPORT
#endif
#include <httplib.h>

#include <optional>
#include <cstdint>
#include <string>

namespace mp = multipass;
namespace mpl = multipass::logging;
namespace json = boost::json;
using mp::api::GrpcBackend;

namespace
{
constexpr auto category = "openai-gateway";

std::string openai_error(std::string_view type, std::string_view message, int /*status*/)
{
    json::object err;
    err["message"] = message;
    err["type"] = type;
    err["code"] = type;
    json::object body;
    body["error"] = err;
    return json::serialize(body);
}

std::string bearer_secret(const httplib::Request& req)
{
    const auto header = req.get_header_value("Authorization");
    constexpr std::string_view prefix = "Bearer ";
    if (header.size() > prefix.size() && header.compare(0, prefix.size(), prefix) == 0)
        return header.substr(prefix.size());
    return {};
}

struct SkAuth
{
    std::string bound_instance_id;
};

std::optional<SkAuth> require_sk_key(GrpcBackend& backend, const httplib::Request& req, httplib::Response& res)
{
    const auto secret = bearer_secret(req);
    if (secret.rfind("sk-elp-", 0) != 0)
    {
        res.status = 401;
        res.set_content(openai_error("invalid_api_key",
                                     "Invalid API key. Use an Electros LaunchPad sk-elp- key, not the matcher token.",
                                     401),
                        "application/json");
        return std::nullopt;
    }
    const auto verified = backend.verify_api_key(secret);
    if (!verified.status.ok() || !verified.reply.valid())
    {
        res.status = 401;
        res.set_content(openai_error("invalid_api_key", "Incorrect API key provided", 401),
                        "application/json");
        return std::nullopt;
    }
    return SkAuth{verified.reply.instance_id()};
}

std::optional<mp::LoadedModelInfo> find_loaded(const mp::ListModelsReply& reply, const std::string& model)
{
    std::optional<mp::LoadedModelInfo> by_model_id;
    for (const auto& info : reply.models())
    {
        if (info.openai_id() == model || info.instance_id() == model)
            return info;
        if (info.model_id() == model)
        {
            if (by_model_id)
                return std::nullopt;
            by_model_id = info;
        }
    }
    return by_model_id;
}

std::string apply_session_max_tokens(std::string body, int32_t cap)
{
    if (cap <= 0)
        return body;
    try
    {
        auto parsed = json::parse(body.empty() ? "{}" : body);
        if (!parsed.is_object())
            return body;
        auto& obj = parsed.as_object();
        const auto clamp_field = [&](const char* key) {
            if (!obj.contains(key))
                return;
            auto& value = obj.at(key);
            if (value.is_int64() && value.as_int64() > cap)
                value = cap;
            else if (value.is_uint64() && value.as_uint64() > static_cast<std::uint64_t>(cap))
                value = cap;
            else if (value.is_double() && value.as_double() > cap)
                value = cap;
        };
        clamp_field("max_tokens");
        clamp_field("max_completion_tokens");
        if (!obj.contains("max_tokens") && !obj.contains("max_completion_tokens"))
            obj["max_tokens"] = cap;
        return json::serialize(parsed);
    }
    catch (const std::exception&)
    {
        return body;
    }
}

void proxy_to_backend(GrpcBackend& backend,
                      const httplib::Request& req,
                      httplib::Response& res,
                      const std::string& path,
                      const SkAuth& auth)
{
    json::value parsed;
    std::string model_id;
    try
    {
        parsed = json::parse(req.body.empty() ? "{}" : req.body);
        if (parsed.is_object() && parsed.as_object().contains("model"))
            model_id = std::string(parsed.as_object().at("model").as_string());
    }
    catch (const std::exception&)
    {
        res.status = 400;
        res.set_content(openai_error("invalid_request_error", "Request body must be JSON", 400),
                        "application/json");
        return;
    }

    const auto listed = backend.list_models();
    if (!listed.status.ok())
    {
        res.status = 503;
        res.set_content(openai_error("api_error", listed.status.error_message(), 503),
                        "application/json");
        return;
    }

    std::optional<mp::LoadedModelInfo> session;
    std::optional<mp::LoadedModelInfo> forbidden_match;
    const auto allows = [&](const mp::LoadedModelInfo& info) {
        return auth.bound_instance_id.empty() || auth.bound_instance_id == info.instance_id();
    };

    if (!model_id.empty())
    {
        if (auto found = find_loaded(listed.reply, model_id))
        {
            if (allows(*found))
                session = found;
            else
                forbidden_match = found;
        }
    }
    else
    {
        std::optional<mp::LoadedModelInfo> only_allowed;
        for (const auto& info : listed.reply.models())
        {
            if (!allows(info))
                continue;
            if (only_allowed)
            {
                only_allowed = std::nullopt;
                break;
            }
            only_allowed = info;
        }
        if (only_allowed)
            session = only_allowed;
    }

    if (!session)
    {
        if (forbidden_match)
        {
            res.status = 403;
            res.set_content(openai_error("invalid_request_error",
                                         "This API key is not authorized for the requested model.",
                                         403),
                            "application/json");
            return;
        }
        res.status = 404;
        res.set_content(openai_error("invalid_request_error",
                                     "The model is not loaded. Load it with elp llm load.",
                                     404),
                        "application/json");
        return;
    }

    httplib::Client client{"127.0.0.1", static_cast<int>(session->port())};
    client.set_read_timeout(600);
    client.set_write_timeout(30);
    client.set_connection_timeout(5);

    const auto outbound = apply_session_max_tokens(req.body, session->max_tokens());
    auto result = client.Post(path, outbound, "application/json");
    if (!result)
    {
        backend.touch_model(session->instance_id(),
                            std::chrono::seconds{10},
                            req.method,
                            path,
                            502);
        mpl::log(mpl::Level::warning, category, "backend proxy failed");
        res.status = 502;
        res.set_content(openai_error("api_error", "inference backend unreachable", 502),
                        "application/json");
        return;
    }
    backend.touch_model(session->instance_id(),
                        std::chrono::seconds{10},
                        req.method,
                        path,
                        result->status);
    const auto content_type = result->get_header_value("Content-Type");
    res.status = result->status;
    res.set_content(result->body,
                    content_type.empty() ? "application/json" : content_type);
}
} // namespace

void mp::api::register_openai_handlers(httplib::Server& server, GrpcBackend& elp_backend)
{
    auto models = [&elp_backend](const httplib::Request& req, httplib::Response& res) {
        const auto auth = require_sk_key(elp_backend, req, res);
        if (!auth)
            return;
        const auto listed = elp_backend.list_models();
        if (!listed.status.ok())
        {
            res.status = 503;
            res.set_content(openai_error("api_error", listed.status.error_message(), 503),
                            "application/json");
            return;
        }
        json::array data;
        for (const auto& model : listed.reply.models())
        {
            if (!auth->bound_instance_id.empty() && auth->bound_instance_id != model.instance_id())
                continue;
            json::object item;
            item["id"] = model.openai_id();
            item["object"] = "model";
            item["owned_by"] = "elp";
            if (model.ctx_size() > 0)
            {
                item["context_length"] = model.ctx_size();
                item["max_model_len"] = model.ctx_size();
            }
            if (model.max_tokens() > 0)
                item["max_tokens"] = model.max_tokens();
            data.push_back(item);
        }
        json::object body;
        body["object"] = "list";
        body["data"] = std::move(data);
        res.status = 200;
        res.set_content(json::serialize(body), "application/json");
    };

    server.Get("/v1/models", models);
    server.Get("/v1/models/:id", models);

    auto completions = [&elp_backend](const httplib::Request& req, httplib::Response& res) {
        const auto auth = require_sk_key(elp_backend, req, res);
        if (!auth)
            return;
        proxy_to_backend(elp_backend, req, res, req.path, *auth);
    };
    server.Post("/v1/chat/completions", completions);
    server.Post("/v1/completions", completions);
    server.Post("/v1/embeddings", completions);
}

void mp::api::register_model_control_handlers(httplib::Server& server, GrpcBackend& backend)
{
    server.Get("/api/v1.0/models/suggested",
               [&backend](const httplib::Request& req, httplib::Response& res) {
                   int limit = 10;
                   if (req.has_param("limit"))
                       limit = std::stoi(req.get_param_value("limit"));
                   const auto use_case = req.get_param_value("use_case");
                   const auto result = backend.find_models(limit, use_case);
                   if (!result.status.ok())
                   {
                       json::object body;
                       body["error"] = result.status.error_message();
                       res.status = 502;
                       res.set_content(json::serialize(body), "application/json");
                       return;
                   }
                   json::array models;
                   for (const auto& model : result.reply.models())
                   {
                       json::object item;
                       item["id"] = model.id();
                       item["name"] = model.name();
                       item["fit_level"] = model.fit_level();
                       item["best_quant"] = model.best_quant();
                       item["memory_required_gb"] = model.memory_required_gb();
                       item["score"] = model.score();
                       item["runtime"] = model.runtime();
                       models.push_back(item);
                   }
                   json::object body;
                   body["models"] = std::move(models);
                   if (!result.reply.reply_message().empty())
                       body["message"] = result.reply.reply_message();
                   res.status = 200;
                   res.set_content(json::serialize(body), "application/json");
               });

    server.Post("/api/v1.0/models/pull",
                [&backend](const httplib::Request& req, httplib::Response& res) {
                    json::object body;
                    try
                    {
                        const auto parsed = json::parse(req.body).as_object();
                        const auto id = std::string(parsed.at("model_id").as_string());
                        const auto quant = parsed.contains("quant")
                                               ? std::string(parsed.at("quant").as_string())
                                               : "";
                        const auto result = backend.pull_model(id, quant);
                        if (!result.status.ok())
                        {
                            body["error"] = result.status.error_message();
                            res.status = 502;
                            res.set_content(json::serialize(body), "application/json");
                            return;
                        }
                        body["model_id"] = result.reply.model_id();
                        body["path"] = result.reply.path();
                        res.status = 200;
                        res.set_content(json::serialize(body), "application/json");
                    }
                    catch (const std::exception& e)
                    {
                        body["error"] = e.what();
                        res.status = 400;
                        res.set_content(json::serialize(body), "application/json");
                    }
                });

    server.Post("/api/v1.0/models/load",
                [&backend](const httplib::Request& req, httplib::Response& res) {
                    json::object body;
                    try
                    {
                        const auto parsed = json::parse(req.body).as_object();
                        const auto id = std::string(parsed.at("model_id").as_string());
                        const auto quant = parsed.contains("quant")
                                               ? std::string(parsed.at("quant").as_string())
                                               : "";
                        const auto ctx = parsed.contains("ctx_size")
                                             ? static_cast<int>(parsed.at("ctx_size").as_int64())
                                             : 4096;
                        const auto max_tokens = parsed.contains("max_tokens")
                                                   ? static_cast<int>(parsed.at("max_tokens").as_int64())
                                                   : 0;
                        const auto result = backend.load_model(id, quant, ctx, max_tokens);
                        if (!result.status.ok())
                        {
                            body["error"] = result.status.error_message();
                            res.status = result.status.error_code() == grpc::RESOURCE_EXHAUSTED
                                             ? 507
                                             : 502;
                            res.set_content(json::serialize(body), "application/json");
                            return;
                        }
                        body["model_id"] = result.reply.model_id();
                        body["instance_id"] = result.reply.instance_id();
                        body["openai_id"] = result.reply.openai_id();
                        body["port"] = result.reply.port();
                        res.status = 200;
                        res.set_content(json::serialize(body), "application/json");
                    }
                    catch (const std::exception& e)
                    {
                        body["error"] = e.what();
                        res.status = 400;
                        res.set_content(json::serialize(body), "application/json");
                    }
                });

    server.Post("/api/v1.0/models/unload",
                [&backend](const httplib::Request& req, httplib::Response& res) {
                    json::object body;
                    try
                    {
                        const auto parsed = json::parse(req.body).as_object();
                        const auto id = std::string(parsed.at("model_id").as_string());
                        const auto result = backend.unload_model(id);
                        if (!result.status.ok())
                        {
                            body["error"] = result.status.error_message();
                            res.status = 502;
                            res.set_content(json::serialize(body), "application/json");
                            return;
                        }
                        body["model_id"] = id;
                        res.status = 200;
                        res.set_content(json::serialize(body), "application/json");
                    }
                    catch (const std::exception& e)
                    {
                        body["error"] = e.what();
                        res.status = 400;
                        res.set_content(json::serialize(body), "application/json");
                    }
                });

    server.Get("/api/v1.0/models",
               [&backend](const httplib::Request&, httplib::Response& res) {
                   const auto result = backend.list_models();
                   json::object body;
                   if (!result.status.ok())
                   {
                       body["error"] = result.status.error_message();
                       res.status = 502;
                       res.set_content(json::serialize(body), "application/json");
                       return;
                   }
                   json::array models;
                   for (const auto& model : result.reply.models())
                   {
                       json::object item;
                       item["model_id"] = model.model_id();
                       item["openai_id"] = model.openai_id();
                       item["backend"] = model.backend();
                       item["port"] = model.port();
                       item["state"] = model.state();
                       models.push_back(item);
                   }
                   body["models"] = std::move(models);
                   res.status = 200;
                   res.set_content(json::serialize(body), "application/json");
               });
}
