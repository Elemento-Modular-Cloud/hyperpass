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
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

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
    std::vector<std::string> bound_instance_ids;

    bool allows(const std::string& instance_id) const
    {
        if (bound_instance_ids.empty())
            return true;
        return std::find(bound_instance_ids.begin(), bound_instance_ids.end(), instance_id) !=
               bound_instance_ids.end();
    }
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
    SkAuth auth;
    if (verified.reply.instance_ids_size() > 0)
    {
        for (const auto& id : verified.reply.instance_ids())
            auth.bound_instance_ids.push_back(id);
    }
    else if (!verified.reply.instance_id().empty())
        auth.bound_instance_ids.push_back(verified.reply.instance_id());
    return auth;
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

int json_int(const json::object& obj, const char* key, int fallback)
{
    if (!obj.contains(key))
        return fallback;
    const auto& value = obj.at(key);
    if (value.is_int64())
        return static_cast<int>(value.as_int64());
    if (value.is_uint64())
        return static_cast<int>(value.as_uint64());
    if (value.is_double())
        return static_cast<int>(value.as_double());
    if (value.is_string())
    {
        try
        {
            return std::stoi(std::string(value.as_string()));
        }
        catch (const std::exception&)
        {
            return fallback;
        }
    }
    return fallback;
}

std::string json_string(const json::object& obj, const char* key)
{
    if (!obj.contains(key) || !obj.at(key).is_string())
        return {};
    return std::string(obj.at(key).as_string());
}

void apply_json_load_params(mp::LlmLoadParams& params, const json::object& obj)
{
    if (obj.contains("ctx_size"))
        params.set_ctx_size(json_int(obj, "ctx_size", 0));
    if (obj.contains("max_tokens"))
        params.set_max_tokens(json_int(obj, "max_tokens", 0));
    if (const auto ngl = json_string(obj, "n_gpu_layers"); !ngl.empty())
        params.set_n_gpu_layers(ngl);
    if (const auto flash = json_string(obj, "flash_attn"); !flash.empty())
        params.set_flash_attn(flash);
    if (const auto ctk = json_string(obj, "cache_type_k"); !ctk.empty())
        params.set_cache_type_k(ctk);
    if (const auto ctv = json_string(obj, "cache_type_v"); !ctv.empty())
        params.set_cache_type_v(ctv);
    if (obj.contains("threads"))
        params.set_threads(json_int(obj, "threads", 0));
    if (obj.contains("threads_batch"))
        params.set_threads_batch(json_int(obj, "threads_batch", 0));
    if (obj.contains("batch_size"))
        params.set_batch_size(json_int(obj, "batch_size", 0));
    if (obj.contains("ubatch_size"))
        params.set_ubatch_size(json_int(obj, "ubatch_size", 0));
    if (obj.contains("parallel"))
        params.set_parallel(json_int(obj, "parallel", 1));
    if (obj.contains("cache_reuse"))
        params.set_cache_reuse(json_int(obj, "cache_reuse", 0));
    if (obj.contains("fit"))
    {
        const auto& value = obj.at("fit");
        if (value.is_bool())
            params.set_fit(value.as_bool());
        else if (value.is_string())
            params.set_fit(std::string(value.as_string()) != "off");
    }
    if (const auto mode = json_string(obj, "load_mode"); !mode.empty())
        params.set_load_mode(mode);
    if (const auto moe = json_string(obj, "moe_offload"); !moe.empty())
        params.set_moe_offload(moe);
    if (obj.contains("n_cpu_moe"))
        params.set_n_cpu_moe(json_int(obj, "n_cpu_moe", 0));
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

bool request_wants_stream(const json::value& parsed)
{
    try
    {
        if (!parsed.is_object())
            return false;
        const auto& obj = parsed.as_object();
        if (!obj.contains("stream"))
            return false;
        const auto& stream = obj.at("stream");
        return stream.is_bool() && stream.as_bool();
    }
    catch (const std::exception&)
    {
        return false;
    }
}

std::string rewrite_upstream_model(std::string body, const std::string& upstream_model_id)
{
    if (upstream_model_id.empty())
        return body;
    try
    {
        auto parsed = json::parse(body.empty() ? "{}" : body);
        if (!parsed.is_object())
            return body;
        parsed.as_object()["model"] = upstream_model_id;
        return json::serialize(parsed);
    }
    catch (const std::exception&)
    {
        return body;
    }
}

/// mlx_lm continuous batching breaks Gemma2 attention masks under concurrency
/// (broadcast of (B,1,L,S) vs (B,n_heads,repeats,L,S)). Setting seed forces
/// the non-batchable sequential path in mlx_lm.server.
/// Also inject stop sequences so the USER:/ASSISTANT: convert_chat fallback
/// (used when a base model has no chat template) cannot loop forever.
std::string sanitize_mlx_request(std::string body)
{
    try
    {
        auto parsed = json::parse(body.empty() ? "{}" : body);
        if (!parsed.is_object())
            return body;
        auto& obj = parsed.as_object();
        if (!obj.contains("seed"))
        {
            static std::atomic<std::uint64_t> seq{1};
            obj["seed"] = static_cast<std::int64_t>(seq.fetch_add(1));
        }
        if (!obj.contains("stop"))
        {
            json::array stops;
            stops.emplace_back("\nUSER:");
            stops.emplace_back("USER:");
            stops.emplace_back("<end_of_turn>");
            stops.emplace_back("<eos>");
            obj["stop"] = std::move(stops);
        }
        return json::serialize(parsed);
    }
    catch (const std::exception&)
    {
        return body;
    }
}

struct UpstreamTarget
{
    std::string scheme;
    std::string host;
    int port{443};
    std::string post_path;
};

std::optional<UpstreamTarget> parse_upstream_target(const std::string& base_url,
                                                    const std::string& request_path)
{
    // base_url like https://api.openai.com/v1
    // request_path like /v1/chat/completions → post /v1/chat/completions on host,
    // using base path when request is /v1/...
    std::string url = base_url;
    while (!url.empty() && url.back() == '/')
        url.pop_back();

    std::string scheme = "https";
    std::string rest = url;
    if (rest.rfind("https://", 0) == 0)
    {
        scheme = "https";
        rest = rest.substr(8);
    }
    else if (rest.rfind("http://", 0) == 0)
    {
        scheme = "http";
        rest = rest.substr(7);
    }
    else
        return std::nullopt;

    const auto slash = rest.find('/');
    std::string hostport = slash == std::string::npos ? rest : rest.substr(0, slash);
    std::string base_path = slash == std::string::npos ? "" : rest.substr(slash);

    int port = scheme == "https" ? 443 : 80;
    const auto colon = hostport.find(':');
    std::string host = hostport;
    if (colon != std::string::npos)
    {
        host = hostport.substr(0, colon);
        try
        {
            port = std::stoi(hostport.substr(colon + 1));
        }
        catch (const std::exception&)
        {
            return std::nullopt;
        }
    }
    if (host.empty())
        return std::nullopt;

    // Map /v1/chat/completions → {base_path}/chat/completions
    std::string suffix = request_path;
    if (suffix.rfind("/v1/", 0) == 0)
        suffix = suffix.substr(3); // keep leading slash of remainder via "/chat/..."
    else if (suffix == "/v1")
        suffix = "";
    if (suffix.empty() || suffix.front() != '/')
        suffix = "/" + suffix;

    UpstreamTarget target;
    target.scheme = scheme;
    target.host = host;
    target.port = port;
    target.post_path = base_path + suffix;
    return target;
}

void forward_response(httplib::Response& res,
                      int status,
                      const std::string& body,
                      const std::string& content_type)
{
    res.status = status;
    res.set_content(body, content_type.empty() ? "application/json" : content_type);
}

void proxy_with_client(std::shared_ptr<httplib::Client> client,
                       GrpcBackend& backend,
                       const httplib::Request& req,
                       httplib::Response& res,
                       const std::string& post_path,
                       const std::string& outbound,
                       const std::string& instance_id,
                       bool stream,
                       const httplib::Headers& headers)
{
    client->set_read_timeout(600);
    client->set_write_timeout(30);
    client->set_connection_timeout(10);

    if (stream)
    {
        // Content provider runs after this handler returns; the Client must
        // outlive that (shared ownership). Capturing a stack Client by
        // reference segfaults once streaming starts.
        auto state = std::make_shared<bool>(false);
        auto ok = std::make_shared<bool>(true);
        auto status_code = std::make_shared<int>(200);

        res.set_header("Cache-Control", "no-cache");
        res.set_header("Connection", "keep-alive");
        res.set_chunked_content_provider(
            "text/event-stream",
            [client,
             post_path,
             outbound,
             headers,
             state,
             ok,
             status_code,
             &backend,
             instance_id = instance_id,
             method = req.method,
             path = req.path](size_t /*offset*/, httplib::DataSink& sink) {
                if (*state)
                    return false;
                *state = true;

                auto result = client->Post(
                    post_path,
                    headers,
                    outbound,
                    "application/json",
                    [&sink](const char* data, size_t len) { return sink.write(data, len); });

                if (!result)
                {
                    *ok = false;
                    *status_code = 502;
                    backend.touch_model(instance_id, std::chrono::seconds{10}, method, path, 502);
                    const auto err =
                        openai_error("api_error", "inference backend unreachable", 502);
                    sink.write(err.data(), err.size());
                    sink.done();
                    return false;
                }
                *status_code = result->status;
                backend.touch_model(instance_id,
                                    std::chrono::seconds{10},
                                    method,
                                    path,
                                    result->status);
                if (result->body.size() && result->status >= 400)
                {
                    if (!result->body.empty())
                        sink.write(result->body.data(), result->body.size());
                }
                sink.done();
                return false;
            });
        res.status = 200;
        return;
    }

    auto result = client->Post(post_path, headers, outbound, "application/json");
    if (!result)
    {
        backend.touch_model(instance_id, std::chrono::seconds{10}, req.method, req.path, 502);
        const auto err = httplib::to_string(result.error());
        mpl::warn(category, "backend proxy failed: {}", err);
        res.status = 502;
        res.set_content(openai_error("api_error", "inference backend unreachable", 502),
                        "application/json");
        return;
    }
    backend.touch_model(instance_id,
                        std::chrono::seconds{10},
                        req.method,
                        req.path,
                        result->status);
    const auto content_type = result->get_header_value("Content-Type");
    forward_response(res,
                     result->status,
                     result->body,
                     content_type.empty() ? "application/json" : content_type);
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
        return auth.allows(info.instance_id());
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
                                     "The model is not loaded. Load it with elp llm load, or add a "
                                     "cloud provider with elp llm provider add.",
                                     404),
                        "application/json");
        return;
    }

    const auto routed = backend.resolve_model_route(session->instance_id());
    if (!routed.status.ok())
    {
        res.status = 503;
        res.set_content(openai_error("api_error", routed.status.error_message(), 503),
                        "application/json");
        return;
    }

    const bool stream = request_wants_stream(parsed);
    auto outbound = apply_session_max_tokens(req.body, routed.reply.max_tokens());

    if (routed.reply.kind() == "openai-compat" || routed.reply.kind() == "openai_compat")
    {
        outbound = rewrite_upstream_model(outbound, routed.reply.upstream_model_id());
        const auto target = parse_upstream_target(routed.reply.base_url(), path);
        if (!target)
        {
            res.status = 502;
            res.set_content(openai_error("api_error", "invalid provider base URL", 502),
                            "application/json");
            return;
        }
        auto client = std::make_shared<httplib::Client>(
            fmt::format("{}://{}:{}", target->scheme, target->host, target->port));
        if (target->scheme == "https")
            client->enable_server_certificate_verification(true);
        httplib::Headers headers{
            {"Authorization", fmt::format("Bearer {}", routed.reply.api_key())},
            {"Accept", stream ? "text/event-stream" : "application/json"},
        };
        if (routed.reply.base_url().find("api.anthropic.com") != std::string::npos)
            headers.emplace("anthropic-version", "2023-06-01");

        proxy_with_client(std::move(client),
                          backend,
                          req,
                          res,
                          target->post_path,
                          outbound,
                          session->instance_id(),
                          stream,
                          headers);
        return;
    }

    if (routed.reply.port() == 0)
    {
        res.status = 502;
        res.set_content(openai_error("api_error", "local inference backend has no port", 502),
                        "application/json");
        return;
    }

    // llama.cpp / vLLM accept our openai_id via --alias / --served-model-name.
    // mlx_lm.server has no alias: it treats `model` as a Hugging Face repo id, so
    // rewrite to the vault path (e.g. mlx-community/Gemma-2-2B-4bit).
    std::string local_upstream = routed.reply.upstream_model_id();
    const auto backend_name = session->backend();
    const bool is_mlx =
        backend_name == "mlx" || backend_name.rfind("mlx", 0) == 0;
    if (local_upstream.empty() && is_mlx)
        local_upstream = session->path();
    outbound = rewrite_upstream_model(outbound, local_upstream);
    if (is_mlx)
        outbound = sanitize_mlx_request(std::move(outbound));

    auto client =
        std::make_shared<httplib::Client>("127.0.0.1", static_cast<int>(routed.reply.port()));
    proxy_with_client(std::move(client),
                      backend,
                      req,
                      res,
                      path,
                      outbound,
                      session->instance_id(),
                      stream,
                      {});
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
            if (!auth->allows(model.instance_id()))
                continue;
            json::object item;
            item["id"] = model.openai_id();
            item["object"] = "model";
            item["owned_by"] =
                model.owned_by().empty()
                    ? (model.backend() == "openai-compat" ? "cloud" : "elp")
                    : model.owned_by();
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
                        const auto ctx = json_int(parsed, "ctx_size", 4096);
                        const auto max_tokens = json_int(parsed, "max_tokens", 0);
                        mp::LlmLoadParams params;
                        apply_json_load_params(params, parsed);
                        if (parsed.contains("params") && parsed.at("params").is_object())
                            apply_json_load_params(params, parsed.at("params").as_object());
                        const auto result = backend.load_model(id, quant, ctx, max_tokens, params);
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
