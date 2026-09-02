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
            cout << fmt::format("{:<28} {:<36} {:<12} {:>6} {:>10} {}\n",
                                "MODEL",
                                "INSTANCE",
                                "BACKEND",
                                "PORT",
                                "RAM",
                                "STATE");
            for (const auto& model : reply.models())
            {
                cout << fmt::format("{:<28} {:<36} {:<12} {:>6} {:>10} {}\n",
                                    model.openai_id(),
                                    model.instance_id(),
                                    model.backend(),
                                    model.port(),
                                    mp::MemorySize::from_bytes(
                                        static_cast<long long>(model.memory_claimed()))
                                        .human_readable(),
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
            auto on_success = [this](CreateApiKeyReply& reply) -> ReturnCodeVariant {
                cout << "Save this API key; it will not be shown again.\n";
                cout << fmt::format("id:     {}\n", reply.id());
                cout << fmt::format("prefix: {}\n", reply.prefix());
                cout << fmt::format("secret: {}\n", reply.secret());
                cout << "Use OPENAI_BASE_URL=https://127.0.0.1:7777/v1 and OPENAI_API_KEY=<secret>\n";
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
                cout << fmt::format("{:<38} {:<12} {}\n", "ID", "PREFIX", "LABEL");
                for (const auto& key : reply.keys())
                    cout << fmt::format("{:<38} {:<12} {}\n",
                                        key.id(),
                                        key.prefix(),
                                        key.label());
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
        cerr << "Usage: hyperpass llm key create|list|revoke [id]\n";
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
    QCommandLineOption ctx_opt{"ctx", "Context size", "ctx", "4096"};
    QCommandLineOption label_opt{"label", "API key label", "label"};
    parser->addOption(use_case_opt);
    parser->addOption(limit_opt);
    parser->addOption(query_opt);
    parser->addOption(recommend_only_opt);
    parser->addOption(quant_opt);
    parser->addOption(ctx_opt);
    parser->addOption(label_opt);

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
        ctx_size = parser->value(ctx_opt).toInt();
    if (parser->isSet(label_opt))
        key_label = parser->value(label_opt);

    const QStringList needs_id{"pull", "load", "unload", "delete", "rm"};
    if (needs_id.contains(subcommand) && model_id.isEmpty())
    {
        cerr << "Missing model id\n";
        return ParseCode::CommandLineError;
    }
    return ParseCode::Ok;
}
