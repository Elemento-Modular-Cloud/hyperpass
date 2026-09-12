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
#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/memory_size.h>

namespace mp = multipass;
namespace cmd = multipass::cmd;

namespace
{
mp::ReturnCodeVariant fail(std::ostream& cerr, grpc::Status& status, const std::string& name)
{
    return cmd::standard_failure_handler_for(name, cerr, status);
}
} // namespace

mp::ReturnCodeVariant cmd::Llm::run(mp::ArgParser* parser)
{
    auto parsed = parse_args(parser);
    if (parsed != ParseCode::Ok)
        return parser->returnCodeFrom(parsed);

    const auto verbosity = parser->verbosityLevel();
    const auto cmd_name = name();

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
        auto on_success = [this](FindModelsReply& reply) -> ReturnCodeVariant {
            if (!reply.reply_message().empty())
                cerr << reply.reply_message() << "\n";
            cout << fmt::format("{:<28} {:<10} {:<10} {:>8} {:>8} {}\n",
                                "MODEL",
                                "FIT",
                                "QUANT",
                                "RAM_GB",
                                "SCORE",
                                "RUNTIME");
            for (const auto& model : reply.models())
            {
                cout << fmt::format("{:<28} {:<10} {:<10} {:>8.1f} {:>8.1f} {}\n",
                                    model.name(),
                                    model.fit_level(),
                                    model.best_quant(),
                                    model.memory_required_gb(),
                                    model.score(),
                                    model.runtime());
            }
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
        AnimatedSpinner spinner{cout};
        spinner.start("Downloading model ");
        auto on_success = [this, &spinner](PullModelReply& reply) -> ReturnCodeVariant {
            spinner.stop();
            cout << fmt::format("Pulled {} -> {}\n", reply.model_id(), reply.path());
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
        *request.mutable_params() = load_params;
        if (load_params.has_ctx_size())
            request.set_ctx_size(load_params.ctx_size());
        if (load_params.has_max_tokens())
            request.set_max_tokens(load_params.max_tokens());
        AnimatedSpinner spinner{cout};
        spinner.start("Loading model ");
        auto on_success = [this, &spinner](LoadModelReply& reply) -> ReturnCodeVariant {
            spinner.stop();
            cout << fmt::format("Loaded {} as {} on 127.0.0.1:{} (instance {}, claimed {})\n",
                                reply.model_id(),
                                reply.openai_id(),
                                reply.port(),
                                reply.instance_id(),
                                mp::MemorySize::from_bytes(
                                    static_cast<long long>(reply.memory_claimed()))
                                    .human_readable());
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
        auto on_success = [this](UnloadModelReply& reply) -> ReturnCodeVariant {
            cout << fmt::format("Unloaded {}\n", reply.model_id());
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
        auto on_success = [this](ListModelsReply& reply) -> ReturnCodeVariant {
            cout << fmt::format("{:<28} {:<36} {:<12} {:>6} {:>10} {:>8} {:>10} {}\n",
                                "MODEL",
                                "INSTANCE",
                                "BACKEND",
                                "PORT",
                                "RAM",
                                "CTX",
                                "MAX_TOK",
                                "STATE");
            for (const auto& model : reply.models())
            {
                cout << fmt::format("{:<28} {:<36} {:<12} {:>6} {:>10} {:>8} {:>10} {}\n",
                                    model.openai_id(),
                                    model.instance_id(),
                                    model.backend(),
                                    model.port(),
                                    mp::MemorySize::from_bytes(
                                        static_cast<long long>(model.memory_claimed()))
                                        .human_readable(),
                                    model.ctx_size() > 0 ? model.ctx_size() : 4096,
                                    model.max_tokens() > 0 ? std::to_string(model.max_tokens())
                                                           : "-",
                                    model.state());
            }
            if (reply.cached_size() > 0)
            {
                cout << "\nCached on disk\n";
                for (const auto& model : reply.cached())
                    cout << fmt::format("  {}  {}\n", model.id(), model.filename());
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
        auto on_success = [this](ListModelsReply& reply) -> ReturnCodeVariant {
            for (const auto& model : reply.cached())
                cout << fmt::format("{}  {}  {:.2f} GiB\n",
                                    model.id(),
                                    model.filename(),
                                    model.memory_required_gb());
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
        auto on_success = [this](DeleteModelReply& reply) -> ReturnCodeVariant {
            cout << fmt::format("Deleted {} (freed {})\n",
                                reply.model_id(),
                                mp::MemorySize::from_bytes(static_cast<long long>(reply.freed_bytes()))
                                    .human_readable());
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
                cout << "Use OPENAI_BASE_URL=https://127.0.0.1:7777/v1 (host) or "
                        "https://192.168.67.1:7777/v1 (from a VM) and OPENAI_API_KEY=<secret>\n";
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
        "Manage local LLM inference behind the OpenAI-compatible /v1 API.\n\n"
        "Subcommands: find, pull, load, unload, list, cache, delete, key create|list|revoke");
}

mp::ParseCode cmd::Llm::parse_args(mp::ArgParser* parser)
{
    parser->addPositionalArgument("subcommand",
                                  "find | pull | load | unload | list | cache | delete | key",
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
    QCommandLineOption label_opt{"label", "API key label", "label"};
    QCommandLineOption instance_opt{"instance", "Bind key to a loaded LLM instance", "instance"};
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
    parser->addOption(label_opt);
    parser->addOption(instance_opt);

    auto status = parser->commandParse(this);
    if (status != ParseCode::Ok)
        return status;

    const auto pos = parser->positionalArguments();
    if (pos.isEmpty())
    {
        cerr << "Missing subcommand. Try: find, pull, load, unload, list, cache, delete, key\n";
        return ParseCode::CommandLineError;
    }
    subcommand = pos.at(0);
    if (pos.size() > 1)
        model_id = pos.at(1);
    if (pos.size() > 2)
        key_id = pos.at(1);
    if (subcommand == "key")
    {
        if (pos.size() > 1)
            key_id = pos.at(1);
        if (pos.size() > 2)
            quant = pos.at(2); // revoke target
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
    if (parser->isSet(label_opt))
        key_label = parser->value(label_opt);
    if (parser->isSet(instance_opt))
        key_instance = parser->value(instance_opt);

    const QStringList needs_id{"pull", "load", "unload", "delete", "rm"};
    if (needs_id.contains(subcommand) && model_id.isEmpty())
    {
        cerr << "Missing model id\n";
        return ParseCode::CommandLineError;
    }
    return ParseCode::Ok;
}
