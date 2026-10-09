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

#include "llm.h"
#include "animated_spinner.h"
#include "common_cli.h"

#include <multipass/cli/argparser.h>
#include <multipass/cli/cli_style.h>
#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/memory_size.h>

#include <QJsonArray>
#include <QJsonObject>

namespace mp = multipass;
namespace cmd = multipass::cmd;
namespace style = multipass::cli_style;

namespace
{
mp::ReturnCodeVariant fail(std::ostream& cerr, grpc::Status& status, const std::string& name)
{
    if (style::json_enabled())
    {
        QJsonObject err;
        err.insert("ok", false);
        err.insert("error", QString::fromStdString(status.error_message()));
        err.insert("command", QString::fromStdString(name));
        style::print_json(cerr, err);
        return mp::ReturnCode::CommandFail;
    }
    return cmd::standard_failure_handler_for(name, cerr, status);
}

std::string format_or_dash(const mp::ModelSuggestion& model)
{
    return model.format().empty() ? "-" : model.format();
}

std::string backends_cell(const mp::ModelSuggestion& model)
{
    if (model.supported_runtimes_size() == 0)
        return "-";
    std::string joined;
    for (int i = 0; i < model.supported_runtimes_size(); ++i)
    {
        if (i)
            joined += ", ";
        joined += model.supported_runtimes(i);
    }
    return joined;
}

QJsonArray backends_json(const mp::ModelSuggestion& model)
{
    QJsonArray arr;
    for (const auto& runtime : model.supported_runtimes())
        arr.push_back(QString::fromStdString(runtime));
    return arr;
}
} // namespace

mp::ReturnCodeVariant cmd::Llm::run(mp::ArgParser* parser)
{
    auto parsed = parse_args(parser);
    if (parsed != ParseCode::Ok)
        return parser->returnCodeFrom(parsed);

    const auto verbosity = parser->verbosityLevel();
    const auto cmd_name = name();
    const bool as_json = parser->jsonOutput() || style::json_enabled();

    if (subcommand == "find")
    {
        FindModelsRequest request;
        request.set_verbosity_level(verbosity);
        request.set_limit(limit);
        request.set_use_case(use_case.toStdString());
        request.set_query(query.toStdString());
        request.set_recommend_only(recommend_only);
        if (!recommend_only)
            request.set_include_too_tight(true);
        auto on_success = [this, as_json](FindModelsReply& reply) -> ReturnCodeVariant {
            if (as_json)
            {
                QJsonArray models;
                for (const auto& model : reply.models())
                {
                    QJsonObject o;
                    o.insert("id", QString::fromStdString(model.id()));
                    o.insert("name", QString::fromStdString(model.name()));
                    o.insert("fit", QString::fromStdString(model.fit_level()));
                    o.insert("quant", QString::fromStdString(model.best_quant()));
                    o.insert("ram_gb", model.memory_required_gb());
                    o.insert("score", model.score());
                    o.insert("runtime", QString::fromStdString(model.runtime()));
                    models.push_back(o);
                }
                QJsonObject root;
                root.insert("models", models);
                if (!reply.reply_message().empty())
                    root.insert("message", QString::fromStdString(reply.reply_message()));
                style::print_json(cout, root);
                return ReturnCode::Ok;
            }
            if (!reply.reply_message().empty())
                style::print_warn(cerr, reply.reply_message());
            style::Table table;
            table.columns = {{"MODEL"}, {"FIT"}, {"QUANT"}, {"RAM_GB", 0, true},
                             {"SCORE", 0, true}, {"RUNTIME"}};
            for (const auto& model : reply.models())
            {
                table.rows.push_back({model.name(),
                                      style::paint_status(model.fit_level()),
                                      model.best_quant(),
                                      fmt::format("{:.1f}", model.memory_required_gb()),
                                      fmt::format("{:.1f}", model.score()),
                                      model.runtime()});
            }
            style::print_table(cout, table);
            return ReturnCode::Ok;
        };
        return dispatch(&RpcMethod::find_models,
                        request,
                        on_success,
                        [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
    }

    if (subcommand == "pull")
    {
        PullModelRequest request;
        request.set_verbosity_level(verbosity);
        request.set_model_id(model_id.toStdString());
        request.set_quant(quant.toStdString());
        // Map --runtime to vault format so vLLM/MLX pulls fetch HF snapshots.
        if (runtime == "vllm")
            request.set_format("hf");
        else if (runtime == "mlx")
            request.set_format("mlx");
        else if (runtime == "llamacpp")
            request.set_format("gguf");
        request.set_background(!pull_wait);
        AnimatedSpinner spinner{cout};
        if (!as_json)
            spinner.start(pull_wait ? "Downloading model " : "Starting download ");
        auto on_success = [this, &spinner, as_json](PullModelReply& reply) -> ReturnCodeVariant {
            spinner.stop();
            if (as_json)
            {
                QJsonObject o;
                o.insert("model_id", QString::fromStdString(reply.model_id()));
                o.insert("path", QString::fromStdString(reply.path()));
                o.insert("message", QString::fromStdString(reply.reply_message()));
                o.insert("background", reply.path().empty());
                style::print_json(cout, o);
                return ReturnCode::Ok;
            }
            if (!reply.path().empty())
                style::print_ok(cout,
                                fmt::format("Pulled {} → {}", reply.model_id(), reply.path()));
            else if (!reply.reply_message().empty())
                style::print_info(cout, reply.reply_message());
            else
                style::print_ok(cout, fmt::format("Pull accepted for {}", reply.model_id()));
            return ReturnCode::Ok;
        };
        auto streaming = [&spinner](const PullModelReply& reply, auto*) {
            if (reply.has_launch_progress() && reply.launch_progress().percent_complete() != "-1")
            {
                spinner.stop();
                spinner.start(fmt::format("Downloading {}% ",
                                          reply.launch_progress().percent_complete()));
            }
            if (!reply.reply_message().empty())
            {
                spinner.stop();
                spinner.start(reply.reply_message() + " ");
            }
        };
        return dispatch(&RpcMethod::pull_model,
                        request,
                        on_success,
                        [&](grpc::Status& s) {
                            spinner.stop();
                            return fail(cerr, s, cmd_name);
                        },
                        streaming);
    }

    if (subcommand == "load")
    {
        LoadModelRequest request;
        request.set_verbosity_level(verbosity);
        request.set_model_id(model_id.toStdString());
        request.set_quant(quant.toStdString());
        request.set_ctx_size(ctx_size);
        request.set_max_tokens(max_tokens);
        if (!runtime.isEmpty())
            request.set_runtime(runtime.toStdString());
        *request.mutable_params() = load_params;
        if (load_params.has_ctx_size())
            request.set_ctx_size(load_params.ctx_size());
        if (load_params.has_max_tokens())
            request.set_max_tokens(load_params.max_tokens());
        if (!intent.isEmpty())
        {
            request.set_intent(intent.toStdString());
            request.set_intent_role(intent_role.toStdString());
        }
        AnimatedSpinner spinner{cout};
        if (!as_json)
            spinner.start("Loading model ");
        auto on_success = [this, &spinner, as_json](LoadModelReply& reply) -> ReturnCodeVariant {
            spinner.stop();
            const auto claimed =
                mp::MemorySize::from_bytes(static_cast<long long>(reply.memory_claimed()))
                    .human_readable();
            if (as_json)
            {
                QJsonObject o;
                o.insert("model_id", QString::fromStdString(reply.model_id()));
                o.insert("openai_id", QString::fromStdString(reply.openai_id()));
                o.insert("instance_id", QString::fromStdString(reply.instance_id()));
                o.insert("port", static_cast<int>(reply.port()));
                o.insert("memory_claimed", QString::fromStdString(claimed));
                o.insert("message", QString::fromStdString(reply.reply_message()));
                style::print_json(cout, o);
                return ReturnCode::Ok;
            }
            if (!reply.reply_message().empty())
                style::print_warn(cerr, reply.reply_message());
            style::print_ok(cout,
                            fmt::format("Loaded {} as {} on 127.0.0.1:{} (instance {}, claimed {})",
                                        reply.model_id(),
                                        reply.openai_id(),
                                        reply.port(),
                                        reply.instance_id(),
                                        claimed));
            return ReturnCode::Ok;
        };
        auto streaming = [&spinner](const LoadModelReply& reply, auto*) {
            if (reply.has_launch_progress())
            {
                spinner.stop();
                spinner.start(fmt::format("Loading {}% ",
                                          reply.launch_progress().percent_complete()));
            }
        };
        return dispatch(&RpcMethod::load_model,
                        request,
                        on_success,
                        [&](grpc::Status& s) {
                            spinner.stop();
                            return fail(cerr, s, cmd_name);
                        },
                        streaming);
    }

    if (subcommand == "unload")
    {
        UnloadModelRequest request;
        request.set_verbosity_level(verbosity);
        request.set_model_id(model_id.toStdString());
        auto on_success = [this, as_json](UnloadModelReply& reply) -> ReturnCodeVariant {
            if (as_json)
            {
                QJsonObject o;
                o.insert("model_id", QString::fromStdString(reply.model_id()));
                o.insert("unloaded", true);
                style::print_json(cout, o);
            }
            else
                style::print_ok(cout, fmt::format("Unloaded {}", reply.model_id()));
            return ReturnCode::Ok;
        };
        return dispatch(&RpcMethod::unload_model,
                        request,
                        on_success,
                        [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
    }

    if (subcommand == "list")
    {
        ListModelsRequest request;
        request.set_verbosity_level(verbosity);
        auto on_success = [this, as_json](ListModelsReply& reply) -> ReturnCodeVariant {
            if (as_json)
            {
                QJsonArray loaded;
                for (const auto& model : reply.models())
                {
                    QJsonObject o;
                    o.insert("openai_id", QString::fromStdString(model.openai_id()));
                    o.insert("instance_id", QString::fromStdString(model.instance_id()));
                    o.insert("backend", QString::fromStdString(model.backend()));
                    o.insert("port", static_cast<int>(model.port()));
                    o.insert("memory_claimed", static_cast<double>(model.memory_claimed()));
                    o.insert("ctx_size", model.ctx_size());
                    o.insert("max_tokens", model.max_tokens());
                    o.insert("state", QString::fromStdString(model.state()));
                    loaded.push_back(o);
                }
                QJsonArray cached;
                for (const auto& model : reply.cached())
                {
                    QJsonObject o;
                    o.insert("id", QString::fromStdString(model.id()));
                    o.insert("filename", QString::fromStdString(model.filename()));
                    o.insert("format", QString::fromStdString(model.format()));
                    o.insert("backends", backends_json(model));
                    o.insert("disk_gb", model.disk_size_gb());
                    o.insert("cache_state", QString::fromStdString(model.cache_state()));
                    o.insert("download_percent", model.download_percent());
                    cached.push_back(o);
                }
                QJsonObject root;
                root.insert("loaded", loaded);
                root.insert("cached", cached);
                style::print_json(cout, root);
                return ReturnCode::Ok;
            }
            style::Table table;
            table.columns = {{"MODEL"},
                             {"INSTANCE"},
                             {"BACKEND"},
                             {"PORT", 0, true},
                             {"RAM", 0, true},
                             {"CTX", 0, true},
                             {"MAX_TOK", 0, true},
                             {"STATE"}};
            for (const auto& model : reply.models())
            {
                const auto port_s =
                    model.port() > 0 ? std::to_string(model.port()) : std::string{"-"};
                const auto ram_s =
                    model.memory_claimed() > 0
                        ? mp::MemorySize::from_bytes(
                              static_cast<long long>(model.memory_claimed()))
                              .human_readable()
                        : std::string{"-"};
                const auto ctx_s =
                    model.ctx_size() > 0 ? std::to_string(model.ctx_size()) : std::string{"-"};
                table.rows.push_back({model.openai_id(),
                                      model.instance_id(),
                                      model.backend(),
                                      port_s,
                                      ram_s,
                                      ctx_s,
                                      model.max_tokens() > 0 ? std::to_string(model.max_tokens())
                                                             : "-",
                                      style::paint_status(model.state())});
            }
            style::print_table(cout, table);
            if (reply.cached_size() > 0)
            {
                cout << "\n" << style::paint(style::Tone::bold, "Cached on disk") << "\n";
                style::Table cache_table;
                cache_table.columns = {{"MODEL"}, {"FORMAT"}, {"BACKENDS"}, {"STATE"}};
                for (const auto& model : reply.cached())
                {
                    std::string state;
                    if (model.cache_state() == "downloading")
                        state = style::paint_status("downloading") +
                                fmt::format(" {}%", model.download_percent());
                    else if (model.cache_state() == "failed")
                        state = style::paint_status("failed");
                    else
                        state = style::paint_status("ready");
                    cache_table.rows.push_back(
                        {model.id(), format_or_dash(model), backends_cell(model), state});
                }
                style::print_table(cout, cache_table);
            }
            return ReturnCode::Ok;
        };
        return dispatch(&RpcMethod::list_models,
                        request,
                        on_success,
                        [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
    }

    if (subcommand == "cache")
    {
        ListModelsRequest request;
        request.set_verbosity_level(verbosity);
        auto on_success = [this, as_json](ListModelsReply& reply) -> ReturnCodeVariant {
            if (as_json)
            {
                QJsonArray cached;
                for (const auto& model : reply.cached())
                {
                    QJsonObject o;
                    o.insert("id", QString::fromStdString(model.id()));
                    o.insert("filename", QString::fromStdString(model.filename()));
                    o.insert("format", QString::fromStdString(model.format()));
                    o.insert("backends", backends_json(model));
                    o.insert("disk_gb", model.memory_required_gb());
                    o.insert("cache_state",
                             QString::fromStdString(model.cache_state().empty() ? "ready"
                                                                               : model.cache_state()));
                    o.insert("download_percent", model.download_percent());
                    cached.push_back(o);
                }
                QJsonObject root;
                root.insert("cached", cached);
                style::print_json(cout, root);
                return ReturnCode::Ok;
            }
            if (reply.cached_size() == 0)
            {
                style::print_info(cout, "No cached models (and no active pulls).");
                return ReturnCode::Ok;
            }
            style::Table table;
            table.columns = {
                {"MODEL"}, {"FORMAT"}, {"BACKENDS"}, {"DETAIL"}, {"SIZE", 0, true}, {"STATE"}};
            for (const auto& model : reply.cached())
            {
                if (model.cache_state() == "downloading")
                {
                    table.rows.push_back({model.id(),
                                          format_or_dash(model),
                                          backends_cell(model),
                                          fmt::format("{}%", model.download_percent()),
                                          "-",
                                          style::paint_status("downloading")});
                    continue;
                }
                if (model.cache_state() == "failed")
                {
                    table.rows.push_back({model.id(),
                                          format_or_dash(model),
                                          backends_cell(model),
                                          model.filename(),
                                          "-",
                                          style::paint_status("failed")});
                    continue;
                }
                table.rows.push_back({model.id(),
                                      format_or_dash(model),
                                      backends_cell(model),
                                      model.filename(),
                                      fmt::format("{:.2f} GiB", model.memory_required_gb()),
                                      style::paint_status("ready")});
            }
            style::print_table(cout, table);
            return ReturnCode::Ok;
        };
        return dispatch(&RpcMethod::list_models,
                        request,
                        on_success,
                        [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
    }

    if (subcommand == "delete" || subcommand == "rm")
    {
        DeleteModelRequest request;
        request.set_verbosity_level(verbosity);
        request.set_model_id(model_id.toStdString());
        auto on_success = [this, as_json](DeleteModelReply& reply) -> ReturnCodeVariant {
            const auto freed =
                mp::MemorySize::from_bytes(static_cast<long long>(reply.freed_bytes()))
                    .human_readable();
            if (as_json)
            {
                QJsonObject o;
                o.insert("model_id", QString::fromStdString(reply.model_id()));
                o.insert("freed", QString::fromStdString(freed));
                style::print_json(cout, o);
            }
            else
                style::print_ok(cout, fmt::format("Deleted {} (freed {})", reply.model_id(), freed));
            return ReturnCode::Ok;
        };
        return dispatch(&RpcMethod::delete_model,
                        request,
                        on_success,
                        [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
    }

    if (subcommand == "key")
    {
        if (key_id == "create" || model_id == "create")
        {
            CreateApiKeyRequest request;
            request.set_verbosity_level(verbosity);
            request.set_label(key_label.toStdString());
            if (!key_instance.isEmpty())
                request.set_instance_id(key_instance.toStdString());
            auto on_success = [this](CreateApiKeyReply& reply) -> ReturnCodeVariant {
                cout << "Save this API key; it will not be shown again.\n";
                cout << fmt::format("id:     {}\n", reply.id());
                cout << fmt::format("prefix: {}\n", reply.prefix());
                if (!reply.instance_id().empty())
                    cout << fmt::format("instance: {} ({})\n", reply.openai_id(), reply.instance_id());
                cout << fmt::format("secret: {}\n", reply.secret());
                cout << fmt::format(
                    "Use OPENAI_BASE_URL=http://127.0.0.1:11434/v1 (host) or "
                    "http://{}:11434/v1 (from a VM) and OPENAI_API_KEY=<secret>\n",
                    mp::default_api_vm_gateway);
                return ReturnCode::Ok;
            };
            return dispatch(&RpcMethod::create_api_key,
                            request,
                            on_success,
                            [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
        }
        if (key_id == "list" || model_id == "list")
        {
            ListApiKeysRequest request;
            request.set_verbosity_level(verbosity);
            auto on_success = [this](ListApiKeysReply& reply) -> ReturnCodeVariant {
                cout << fmt::format("{:<38} {:<12} {:<28} {}\n", "ID", "PREFIX", "INSTANCE", "LABEL");
                for (const auto& key : reply.keys())
                {
                    std::string instance = "global";
                    if (key.instance_ids_size() > 1)
                        instance = fmt::format("{} instances", key.instance_ids_size());
                    else if (key.instance_ids_size() == 1)
                        instance = key.openai_id().empty() ? key.instance_ids(0) : key.openai_id();
                    else if (!key.instance_id().empty())
                        instance = key.openai_id().empty() ? key.instance_id() : key.openai_id();
                    cout << fmt::format("{:<38} {:<12} {:<28} {}\n",
                                        key.id(),
                                        key.prefix(),
                                        instance,
                                        key.label());
                }
                return ReturnCode::Ok;
            };
            return dispatch(&RpcMethod::list_api_keys,
                            request,
                            on_success,
                            [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
        }
        if (key_id == "revoke" || model_id == "revoke")
        {
            RevokeApiKeyRequest request;
            request.set_verbosity_level(verbosity);
            request.set_id(quant.toStdString());
            request.set_prefix(quant.toStdString());
            auto on_success = [this](RevokeApiKeyReply& reply) -> ReturnCodeVariant {
                cout << fmt::format("Revoked {}\n", reply.id());
                return ReturnCode::Ok;
            };
            return dispatch(&RpcMethod::revoke_api_key,
                            request,
                            on_success,
                            [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
        }
        cerr << "Usage: elp llm key create|list|revoke [id]\n";
        cerr << "  create [--label NAME] [--instance INSTANCE_ID]\n";
        return ReturnCode::CommandLineError;
    }

    if (subcommand == "provider")
    {
        const auto action = key_id.isEmpty() ? model_id : key_id;
        if (action == "add")
        {
            CreateLlmProviderRequest request;
            request.set_verbosity_level(verbosity);
            request.set_label(key_label.toStdString());
            request.set_preset(provider_preset.toStdString());
            request.set_base_url(provider_base_url.toStdString());
            request.set_api_key(provider_api_key.toStdString());
            request.set_refresh(true);
            for (const auto& pat : provider_include)
                request.add_include(pat.toStdString());
            for (const auto& pat : provider_exclude)
                request.add_exclude(pat.toStdString());
            AnimatedSpinner spinner{cout};
            spinner.start("Connecting provider ");
            auto on_success = [this, &spinner](CreateLlmProviderReply& reply) -> ReturnCodeVariant {
                spinner.stop();
                const auto& p = reply.provider();
                cout << fmt::format("Provider {} ({}) — {} models exposed\n",
                                    p.label(),
                                    p.id(),
                                    p.model_count());
                cout << fmt::format("  base_url: {}\n", p.base_url());
                cout << fmt::format("  key:      {}…\n", p.key_prefix());
                if (!reply.log_line().empty())
                    cout << reply.log_line() << "\n";
                return ReturnCode::Ok;
            };
            return dispatch(&RpcMethod::create_llm_provider,
                            request,
                            on_success,
                            [&](grpc::Status& s) {
                                spinner.stop();
                                return fail(cerr, s, cmd_name);
                            });
        }
        if (action == "list")
        {
            ListLlmProvidersRequest request;
            request.set_verbosity_level(verbosity);
            auto on_success = [this](ListLlmProvidersReply& reply) -> ReturnCodeVariant {
                cout << fmt::format("{:<38} {:<14} {:>6} {}\n", "ID", "PRESET", "MODELS", "LABEL");
                for (const auto& p : reply.providers())
                {
                    cout << fmt::format("{:<38} {:<14} {:>6} {}\n",
                                        p.id(),
                                        p.preset(),
                                        p.model_count(),
                                        p.label());
                    cout << fmt::format("  {}\n", p.base_url());
                }
                return ReturnCode::Ok;
            };
            return dispatch(&RpcMethod::list_llm_providers,
                            request,
                            on_success,
                            [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
        }
        if (action == "update")
        {
            if (quant.isEmpty())
            {
                cerr << "Usage: elp llm provider update <id> [--label ...] [--base-url ...] "
                        "[--key ...] [--include ...] [--exclude ...]\n";
                return ReturnCode::CommandLineError;
            }
            UpdateLlmProviderRequest request;
            request.set_verbosity_level(verbosity);
            request.set_id(quant.toStdString());
            if (!key_label.isEmpty())
            {
                request.set_label(key_label.toStdString());
                request.set_update_label(true);
            }
            if (!provider_base_url.isEmpty())
            {
                request.set_base_url(provider_base_url.toStdString());
                request.set_update_base_url(true);
            }
            if (!provider_api_key.isEmpty())
            {
                request.set_api_key(provider_api_key.toStdString());
                request.set_update_api_key(true);
            }
            if (!provider_include.isEmpty())
            {
                for (const auto& pat : provider_include)
                    request.add_include(pat.toStdString());
                request.set_update_include(true);
            }
            if (!provider_exclude.isEmpty())
            {
                for (const auto& pat : provider_exclude)
                    request.add_exclude(pat.toStdString());
                request.set_update_exclude(true);
            }
            request.set_refresh(true);
            auto on_success = [this](UpdateLlmProviderReply& reply) -> ReturnCodeVariant {
                cout << fmt::format("Updated {} — {} models\n",
                                    reply.provider().id(),
                                    reply.provider().model_count());
                return ReturnCode::Ok;
            };
            return dispatch(&RpcMethod::update_llm_provider,
                            request,
                            on_success,
                            [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
        }
        if (action == "rm" || action == "delete")
        {
            if (quant.isEmpty())
            {
                cerr << "Usage: elp llm provider rm <id>\n";
                return ReturnCode::CommandLineError;
            }
            DeleteLlmProviderRequest request;
            request.set_verbosity_level(verbosity);
            request.set_id(quant.toStdString());
            auto on_success = [this](DeleteLlmProviderReply& reply) -> ReturnCodeVariant {
                cout << fmt::format("Removed provider {} ({} models)\n",
                                    reply.id(),
                                    reply.models_removed());
                return ReturnCode::Ok;
            };
            return dispatch(&RpcMethod::delete_llm_provider,
                            request,
                            on_success,
                            [&](grpc::Status& s) { return fail(cerr, s, cmd_name); });
        }
        if (action == "refresh")
        {
            if (quant.isEmpty())
            {
                cerr << "Usage: elp llm provider refresh <id>\n";
                return ReturnCode::CommandLineError;
            }
            RefreshLlmProviderRequest request;
            request.set_verbosity_level(verbosity);
            request.set_id(quant.toStdString());
            AnimatedSpinner spinner{cout};
            spinner.start("Refreshing provider models ");
            auto on_success = [this, &spinner](RefreshLlmProviderReply& reply) -> ReturnCodeVariant {
                spinner.stop();
                cout << fmt::format("Refreshed {}: +{} -{} kept {}\n",
                                    reply.provider().id(),
                                    reply.models_added(),
                                    reply.models_removed(),
                                    reply.models_kept());
                return ReturnCode::Ok;
            };
            return dispatch(&RpcMethod::refresh_llm_provider,
                            request,
                            on_success,
                            [&](grpc::Status& s) {
                                spinner.stop();
                                return fail(cerr, s, cmd_name);
                            });
        }
        cerr << "Usage: elp llm provider add|list|update|rm|refresh\n";
        cerr << "  add --key SECRET [--preset openai|openrouter|anthropic] [--base-url URL]\n";
        cerr << "      [--label NAME] [--include GLOB] [--exclude GLOB]\n";
        return ReturnCode::CommandLineError;
    }

    cerr << "Unknown llm subcommand\n";
    return ReturnCode::CommandLineError;
}

std::string cmd::Llm::name() const
{
    return "llm";
}

QString cmd::Llm::short_help() const
{
    return QStringLiteral("Find, pull, load, and serve local models");
}

QString cmd::Llm::description() const
{
    return QStringLiteral(
        "Manage local and cloud LLM inference behind the OpenAI-compatible /v1 API.\n\n"
        "Subcommands: find, pull, load, unload, list, cache, delete, key create|list|revoke,\n"
        "             provider add|list|update|rm|refresh\n"
        "Pull downloads in the background by default (use --wait to block). "
        "Load only starts models that are already in the cache.");
}

mp::ParseCode cmd::Llm::parse_args(mp::ArgParser* parser)
{
    parser->addPositionalArgument("subcommand",
                                  "find | pull | load | unload | list | cache | delete | key | "
                                  "provider",
                                  "<subcommand>");
    parser->addPositionalArgument("args", "Subcommand arguments", "[<args>...]");
    QCommandLineOption use_case_opt{"use-case", "Recommendation use case", "use-case"};
    QCommandLineOption limit_opt{"limit", "Number of suggestions", "limit", "10"};
    QCommandLineOption query_opt{"query", "Catalog search query", "query"};
    QCommandLineOption recommend_only_opt{
        "recommend-only", "Return llmfit recommendations only (default: browse catalog)"};
    QCommandLineOption quant_opt{"quant", "GGUF quantization", "quant"};
    QCommandLineOption ctx_opt{"ctx", "Context window size (--ctx-size)", "ctx", "4096"};
    QCommandLineOption max_tokens_opt{"max-tokens",
                                      "Default/cap for OpenAI max_tokens (0 = unlimited)",
                                      "n",
                                      "0"};
    QCommandLineOption ngl_opt{"n-gpu-layers", "GPU layers: auto, all, or a count", "n"};
    QCommandLineOption flash_opt{"flash-attn", "Flash attention: auto, on, or off", "mode"};
    QCommandLineOption ctk_opt{"cache-type-k", "KV cache type for K (f16, q8_0, q4_0)", "type"};
    QCommandLineOption ctv_opt{"cache-type-v", "KV cache type for V (f16, q8_0, q4_0)", "type"};
    QCommandLineOption threads_opt{"threads", "CPU threads for generation", "n"};
    QCommandLineOption threads_batch_opt{"threads-batch", "CPU threads for prompt batching", "n"};
    QCommandLineOption batch_opt{"batch-size", "Logical batch size", "n"};
    QCommandLineOption ubatch_opt{"ubatch-size", "Physical micro-batch size", "n"};
    QCommandLineOption parallel_opt{"parallel", "Server slots", "n"};
    QCommandLineOption cache_reuse_opt{"cache-reuse", "Min chunk size for KV cache reuse", "n"};
    QCommandLineOption fit_opt{"fit", "Fit unset args to device memory: on or off", "mode"};
    QCommandLineOption load_mode_opt{"load-mode",
                                     "Model load mode: auto, mmap, mlock, mmap+mlock",
                                     "mode"};
    QCommandLineOption moe_opt{"moe-offload", "MoE expert placement: auto, cpu, or off", "mode"};
    QCommandLineOption cpu_moe_opt{"cpu-moe", "Keep MoE expert weights on CPU"};
    QCommandLineOption n_cpu_moe_opt{"n-cpu-moe", "Keep the first N MoE layers on CPU", "n"};
    QCommandLineOption runtime_opt{"runtime",
                                   "Inference runtime: llamacpp, vllm, or mlx",
                                   "runtime"};
    QCommandLineOption wait_opt{"wait",
                                "For pull: block until download finishes (default: background)"};
    QCommandLineOption dtype_opt{"dtype",
                                 "vLLM dtype: auto, float16, bfloat16, …",
                                 "dtype"};
    QCommandLineOption gpu_mem_opt{"gpu-memory-utilization",
                                   "vLLM GPU memory fraction (0–1; try 0.80 on GB10)",
                                   "frac"};
    QCommandLineOption max_model_len_opt{"max-model-len",
                                        "vLLM max sequence length (defaults to --ctx)",
                                        "n"};
    QCommandLineOption label_opt{"label", "API key / provider label", "label"};
    QCommandLineOption instance_opt{"instance", "Bind key to a loaded LLM instance", "instance"};
    QCommandLineOption intent_opt{
        "intent", "Join (or create) this named intent when loading", "intent"};
    QCommandLineOption intent_role_opt{
        "intent-role", "This instance's role within --intent (required if --intent is set)", "role"};
    QCommandLineOption preset_opt{"preset",
                                  "Cloud provider preset: openai, openrouter, anthropic",
                                  "preset"};
    QCommandLineOption base_url_opt{"base-url", "OpenAI-compatible API base URL", "url"};
    QCommandLineOption api_key_opt{{"key", "api-key"}, "Upstream provider API key", "secret"};
    QCommandLineOption include_opt{"include",
                                   "Only expose model ids matching this glob (repeatable)",
                                   "glob"};
    QCommandLineOption exclude_opt{"exclude",
                                   "Hide model ids matching this glob (repeatable)",
                                   "glob"};
    parser->addOption(use_case_opt);
    parser->addOption(limit_opt);
    parser->addOption(query_opt);
    parser->addOption(recommend_only_opt);
    parser->addOption(quant_opt);
    parser->addOption(ctx_opt);
    parser->addOption(max_tokens_opt);
    parser->addOption(ngl_opt);
    parser->addOption(flash_opt);
    parser->addOption(ctk_opt);
    parser->addOption(ctv_opt);
    parser->addOption(threads_opt);
    parser->addOption(threads_batch_opt);
    parser->addOption(batch_opt);
    parser->addOption(ubatch_opt);
    parser->addOption(parallel_opt);
    parser->addOption(cache_reuse_opt);
    parser->addOption(fit_opt);
    parser->addOption(load_mode_opt);
    parser->addOption(moe_opt);
    parser->addOption(cpu_moe_opt);
    parser->addOption(n_cpu_moe_opt);
    parser->addOption(runtime_opt);
    parser->addOption(wait_opt);
    parser->addOption(dtype_opt);
    parser->addOption(gpu_mem_opt);
    parser->addOption(max_model_len_opt);
    parser->addOption(label_opt);
    parser->addOption(instance_opt);
    parser->addOption(intent_opt);
    parser->addOption(intent_role_opt);
    parser->addOption(preset_opt);
    parser->addOption(base_url_opt);
    parser->addOption(api_key_opt);
    parser->addOption(include_opt);
    parser->addOption(exclude_opt);

    auto status = parser->commandParse(this);
    if (status != ParseCode::Ok)
        return status;

    const auto pos = parser->positionalArguments();
    if (pos.isEmpty())
    {
        cerr << "Missing subcommand. Try: find, pull, load, unload, list, cache, delete, key, "
                "provider\n";
        return ParseCode::CommandLineError;
    }
    subcommand = pos.at(0);
    if (pos.size() > 1)
        model_id = pos.at(1);
    if (pos.size() > 2)
        key_id = pos.at(1);
    if (subcommand == "key" || subcommand == "provider")
    {
        if (pos.size() > 1)
            key_id = pos.at(1);
        if (pos.size() > 2)
            quant = pos.at(2); // revoke/update/rm/refresh target id
        model_id = key_id;
    }
    if (parser->isSet(use_case_opt))
        use_case = parser->value(use_case_opt);
    if (parser->isSet(limit_opt))
        limit = parser->value(limit_opt).toInt();
    if (parser->isSet(query_opt))
        query = parser->value(query_opt);
    recommend_only = parser->isSet(recommend_only_opt);
    if (parser->isSet(quant_opt))
        quant = parser->value(quant_opt);
    if (parser->isSet(ctx_opt))
    {
        ctx_size = parser->value(ctx_opt).toInt();
        load_params.set_ctx_size(ctx_size);
    }
    if (parser->isSet(max_tokens_opt))
    {
        max_tokens = parser->value(max_tokens_opt).toInt();
        load_params.set_max_tokens(max_tokens);
    }
    if (parser->isSet(ngl_opt))
        load_params.set_n_gpu_layers(parser->value(ngl_opt).toStdString());
    if (parser->isSet(flash_opt))
        load_params.set_flash_attn(parser->value(flash_opt).toStdString());
    if (parser->isSet(ctk_opt))
        load_params.set_cache_type_k(parser->value(ctk_opt).toStdString());
    if (parser->isSet(ctv_opt))
        load_params.set_cache_type_v(parser->value(ctv_opt).toStdString());
    if (parser->isSet(threads_opt))
        load_params.set_threads(parser->value(threads_opt).toInt());
    if (parser->isSet(threads_batch_opt))
        load_params.set_threads_batch(parser->value(threads_batch_opt).toInt());
    if (parser->isSet(batch_opt))
        load_params.set_batch_size(parser->value(batch_opt).toInt());
    if (parser->isSet(ubatch_opt))
        load_params.set_ubatch_size(parser->value(ubatch_opt).toInt());
    if (parser->isSet(parallel_opt))
        load_params.set_parallel(parser->value(parallel_opt).toInt());
    if (parser->isSet(cache_reuse_opt))
        load_params.set_cache_reuse(parser->value(cache_reuse_opt).toInt());
    if (parser->isSet(fit_opt))
        load_params.set_fit(parser->value(fit_opt).toLower() != "off");
    if (parser->isSet(load_mode_opt))
        load_params.set_load_mode(parser->value(load_mode_opt).toStdString());
    if (parser->isSet(moe_opt))
        load_params.set_moe_offload(parser->value(moe_opt).toStdString());
    if (parser->isSet(cpu_moe_opt))
        load_params.set_moe_offload("cpu");
    if (parser->isSet(n_cpu_moe_opt))
        load_params.set_n_cpu_moe(parser->value(n_cpu_moe_opt).toInt());
    if (parser->isSet(runtime_opt))
        runtime = parser->value(runtime_opt).trimmed().toLower();
    pull_wait = parser->isSet(wait_opt);
    if (parser->isSet(dtype_opt))
        load_params.set_dtype(parser->value(dtype_opt).toStdString());
    if (parser->isSet(gpu_mem_opt))
    {
        bool ok = false;
        const auto frac = parser->value(gpu_mem_opt).toDouble(&ok);
        if (!ok || frac <= 0.0 || frac > 1.0)
        {
            cerr << "--gpu-memory-utilization must be a number in (0, 1]\n";
            return ParseCode::CommandLineError;
        }
        load_params.set_gpu_memory_utilization(frac);
    }
    if (parser->isSet(max_model_len_opt))
        load_params.set_max_model_len(parser->value(max_model_len_opt).toInt());
    if (parser->isSet(label_opt))
        key_label = parser->value(label_opt);
    if (parser->isSet(instance_opt))
        key_instance = parser->value(instance_opt);
    if (parser->isSet(intent_opt))
        intent = parser->value(intent_opt);
    if (parser->isSet(intent_role_opt))
        intent_role = parser->value(intent_role_opt);
    if (parser->isSet(preset_opt))
        provider_preset = parser->value(preset_opt);
    if (parser->isSet(base_url_opt))
        provider_base_url = parser->value(base_url_opt);
    if (parser->isSet(api_key_opt))
        provider_api_key = parser->value(api_key_opt);
    if (parser->isSet(include_opt))
        provider_include = parser->values(include_opt);
    if (parser->isSet(exclude_opt))
        provider_exclude = parser->values(exclude_opt);

    const QStringList needs_id{"pull", "load", "unload", "delete", "rm"};
    if (needs_id.contains(subcommand) && model_id.isEmpty())
    {
        cerr << "Missing model id\n";
        return ParseCode::CommandLineError;
    }
    if (subcommand == "load" && !intent.isEmpty() && intent_role.isEmpty())
    {
        cerr << "--intent requires --intent-role\n";
        return ParseCode::CommandLineError;
    }
    if (subcommand == "provider" && (key_id == "add" || model_id == "add") &&
        provider_api_key.isEmpty())
    {
        cerr << "provider add requires --key\n";
        return ParseCode::CommandLineError;
    }
    return ParseCode::Ok;
}
