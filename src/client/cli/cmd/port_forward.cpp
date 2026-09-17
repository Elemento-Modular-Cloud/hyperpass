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

#include "port_forward.h"

#include "common_cli.h"

#include <multipass/cli/argparser.h>
#include <multipass/format.h>

namespace mp = multipass;
namespace cmd = multipass::cmd;

namespace
{
const QCommandLineOption guest_port_option{"guest-port",
                                           "Guest TCP port to forward to (defaults to host port).",
                                           "port"};
const QCommandLineOption bind_option{"bind",
                                     "Host address to bind (default: 127.0.0.1).",
                                     "address",
                                     "127.0.0.1"};
} // namespace

mp::ReturnCodeVariant cmd::PortForward::run(ArgParser* parser)
{
    parser->addPositionalArgument("action", "add | list | remove", "<action>");
    parser->addPositionalArgument(
        "args",
        "For add: <instance> <host-port>. For list: optional <instance>. "
        "For remove: <id> or <instance:host-port>.",
        "[<args>…]");
    parser->addOption(guest_port_option);
    parser->addOption(bind_option);

    const auto status = parser->commandParse(this);
    if (status != ParseCode::Ok)
        return parser->returnCodeFrom(status);

    const auto args = parser->positionalArguments();
    if (args.empty())
    {
        cerr << "Please specify an action: add, list, or remove.\n";
        return parser->returnCodeFrom(ParseCode::CommandLineError);
    }

    const auto action = args[0].toStdString();
    if (action == "add")
        return run_add(parser);
    if (action == "list")
        return run_list(parser);
    if (action == "remove")
        return run_remove(parser);

    cerr << fmt::format("Unknown action \"{}\"; expected add, list, or remove.\n", action);
    return parser->returnCodeFrom(ParseCode::CommandLineError);
}

std::string cmd::PortForward::name() const
{
    return "port-forward";
}

std::vector<std::string> cmd::PortForward::aliases() const
{
    return {name(), "portforward"};
}

QString cmd::PortForward::short_help() const
{
    return QStringLiteral("Forward host TCP ports to guest instance ports");
}

QString cmd::PortForward::description() const
{
    return QStringLiteral(
        "Map a host TCP port to a guest instance management IP and port "
        "(L4 pass-through).\n\n"
        "  elp port-forward add <instance> <host-port> [--guest-port N] [--bind 127.0.0.1]\n"
        "  elp port-forward list [<instance>]\n"
        "  elp port-forward remove <id|instance:host-port>");
}

mp::ReturnCodeVariant cmd::PortForward::run_add(ArgParser* parser)
{
    const auto args = parser->positionalArguments();
    if (args.size() < 3)
    {
        cerr << "Please provide an instance name and host port.\n";
        return parser->returnCodeFrom(ParseCode::CommandLineError);
    }

    bool ok = false;
    const int host_port = args[2].toInt(&ok);
    if (!ok || host_port <= 0 || host_port > 65535)
    {
        cerr << "Host port must be an integer between 1 and 65535.\n";
        return parser->returnCodeFrom(ParseCode::CommandLineError);
    }

    int guest_port = host_port;
    if (parser->isSet(guest_port_option))
    {
        guest_port = parser->value(guest_port_option).toInt(&ok);
        if (!ok || guest_port <= 0 || guest_port > 65535)
        {
            cerr << "Guest port must be an integer between 1 and 65535.\n";
            return parser->returnCodeFrom(ParseCode::CommandLineError);
        }
    }

    AddPortForwardRequest request;
    request.set_instance(args[1].toStdString());
    request.set_host_port(host_port);
    request.set_guest_port(guest_port);
    request.set_host_bind(parser->value(bind_option).toStdString());
    request.set_verbosity_level(parser->verbosityLevel());

    auto on_success = [this](AddPortForwardReply& reply) -> ReturnCodeVariant {
        cout << reply.reply_message() << "\n";
        return ReturnCode::Ok;
    };
    auto on_failure = [this](grpc::Status& status, AddPortForwardReply& reply) -> ReturnCodeVariant {
        return standard_failure_handler_for(name(), cerr, status, reply.reply_message());
    };

    return dispatch(&RpcMethod::add_port_forward, request, on_success, on_failure);
}

mp::ReturnCodeVariant cmd::PortForward::run_list(ArgParser* parser)
{
    const auto args = parser->positionalArguments();
    ListPortForwardsRequest request;
    request.set_verbosity_level(parser->verbosityLevel());
    if (args.size() >= 2)
        request.set_instance(args[1].toStdString());

    auto on_success = [this](ListPortForwardsReply& reply) -> ReturnCodeVariant {
        if (reply.forwards().empty())
        {
            cout << "No port forwards found.\n";
            return ReturnCode::Ok;
        }

        for (const auto& forward : reply.forwards())
        {
            const auto target = forward.guest_ip().empty()
                                    ? fmt::format("{}:{}", forward.instance(), forward.guest_port())
                                    : fmt::format("{}:{} ({})",
                                                  forward.guest_ip(),
                                                  forward.guest_port(),
                                                  forward.instance());
            cout << fmt::format("{}  {}:{} → {}  [{}] {}\n",
                                forward.id(),
                                forward.host_bind(),
                                forward.host_port(),
                                target,
                                forward.active() ? "active" : "inactive",
                                forward.status_message());
        }
        return ReturnCode::Ok;
    };
    auto on_failure = [this](grpc::Status& status, ListPortForwardsReply&) -> ReturnCodeVariant {
        return standard_failure_handler_for(name(), cerr, status);
    };

    return dispatch(&RpcMethod::list_port_forwards, request, on_success, on_failure);
}

mp::ReturnCodeVariant cmd::PortForward::run_remove(ArgParser* parser)
{
    const auto args = parser->positionalArguments();
    if (args.size() < 2)
    {
        cerr << "Please provide a port forward id or instance:host-port.\n";
        return parser->returnCodeFrom(ParseCode::CommandLineError);
    }

    const auto selector = args[1].toStdString();
    std::string id = selector;

    const auto colon = selector.rfind(':');
    if (colon != std::string::npos && colon + 1 < selector.size())
    {
        bool ok = false;
        const int host_port = QString::fromStdString(selector.substr(colon + 1)).toInt(&ok);
        if (ok && host_port > 0 && host_port <= 65535)
        {
            const auto instance = selector.substr(0, colon);
            ListPortForwardsRequest list_request;
            list_request.set_instance(instance);
            list_request.set_verbosity_level(parser->verbosityLevel());

            std::string resolved_id;
            auto on_list_success = [&](ListPortForwardsReply& reply) -> ReturnCodeVariant {
                for (const auto& forward : reply.forwards())
                {
                    if (forward.host_port() == host_port)
                    {
                        resolved_id = forward.id();
                        break;
                    }
                }
                if (resolved_id.empty())
                {
                    cerr << fmt::format("No port forward for {}:{}\n", instance, host_port);
                    return ReturnCode::CommandLineError;
                }
                return ReturnCode::Ok;
            };
            auto on_list_failure = [this](grpc::Status& status,
                                          ListPortForwardsReply&) -> ReturnCodeVariant {
                return standard_failure_handler_for(name(), cerr, status);
            };

            const auto list_rc = dispatch(&RpcMethod::list_port_forwards,
                                          list_request,
                                          on_list_success,
                                          on_list_failure);
            if (list_rc != ReturnCode::Ok)
                return list_rc;
            id = resolved_id;
        }
    }

    RemovePortForwardRequest request;
    request.set_id(id);
    request.set_verbosity_level(parser->verbosityLevel());

    auto on_success = [this](RemovePortForwardReply& reply) -> ReturnCodeVariant {
        cout << reply.reply_message() << "\n";
        return ReturnCode::Ok;
    };
    auto on_failure = [this](grpc::Status& status,
                             RemovePortForwardReply& reply) -> ReturnCodeVariant {
        return standard_failure_handler_for(name(), cerr, status, reply.reply_message());
    };

    return dispatch(&RpcMethod::remove_port_forward, request, on_success, on_failure);
}
