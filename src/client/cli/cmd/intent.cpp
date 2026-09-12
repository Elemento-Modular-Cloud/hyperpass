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

#include "intent.h"

#include "animated_spinner.h"
#include "common_cli.h"

#include <multipass/cli/argparser.h>
#include <multipass/format.h>

#include <QFile>
#include <QTextStream>

namespace mp = multipass;
namespace cmd = multipass::cmd;

namespace
{
const QCommandLineOption service_option{
    "service",
    "Add a member using a known service template (e.g. redis, postgres). Can be repeated.",
    "role"};
const QCommandLineOption instance_option{
    "instance",
    "Add a custom member as role:image:cloud-init-file:cores:mem:disk (trailing fields "
    "optional, e.g. \"cache:22.04::1:1G:5G\"). Can be repeated.",
    "spec"};
const QCommandLineOption purge_option{"purge", "Also purge deleted member instances immediately."};

std::string instance_status_name(mp::InstanceStatus::Status status)
{
    switch (status)
    {
    case mp::InstanceStatus::RUNNING:
        return "Running";
    case mp::InstanceStatus::STOPPED:
        return "Stopped";
    case mp::InstanceStatus::DELETED:
        return "Deleted";
    case mp::InstanceStatus::SUSPENDED:
        return "Suspended";
    case mp::InstanceStatus::SUSPENDING:
        return "Suspending";
    default:
        return "Unknown";
    }
}
} // namespace

mp::ReturnCodeVariant cmd::Intent::run(ArgParser* parser)
{
    parser->addPositionalArgument("action", "create | list | info | delete", "<action>");
    parser->addPositionalArgument("name", "The intent's name (not needed for `list`)", "[<name>]");
    parser->addOption(service_option);
    parser->addOption(instance_option);
    parser->addOption(purge_option);

    const auto status = parser->commandParse(this);
    if (status != ParseCode::Ok)
        return parser->returnCodeFrom(status);

    const auto args = parser->positionalArguments();
    if (args.empty())
    {
        cerr << "Please specify an action: create, list, info, or delete.\n";
        return parser->returnCodeFrom(ParseCode::CommandLineError);
    }

    const auto action = args[0].toStdString();
    if (action == "create")
        return run_create(parser);
    if (action == "list")
        return run_list(parser);
    if (action == "info")
        return run_info(parser);
    if (action == "delete")
        return run_delete(parser);

    cerr << fmt::format("Unknown action \"{}\"; expected create, list, info, or delete.\n", action);
    return parser->returnCodeFrom(ParseCode::CommandLineError);
}

std::string cmd::Intent::name() const
{
    return "intent";
}

QString cmd::Intent::short_help() const
{
    return QStringLiteral("Create and manage intents (named groups of instances)");
}

QString cmd::Intent::description() const
{
    return QStringLiteral(
        "Create a named group of instances launched together (e.g. a \"redis\" and a "
        "\"postgres\" instance for an app), and list, inspect, or delete such groups.\n\n"
        "  elp intent create <name> --service redis --service postgres\n"
        "  elp intent list\n"
        "  elp intent info <name>\n"
        "  elp intent delete <name> [--purge]");
}

mp::ReturnCodeVariant cmd::Intent::run_create(ArgParser* parser)
{
    const auto args = parser->positionalArguments();
    if (args.size() < 2)
    {
        cerr << "Please provide a name for the intent.\n";
        return parser->returnCodeFrom(ParseCode::CommandLineError);
    }
    if (!parser->isSet(service_option) && !parser->isSet(instance_option))
    {
        cerr << "Please specify at least one member with --service or --instance.\n";
        return parser->returnCodeFrom(ParseCode::CommandLineError);
    }

    IntentCreateRequest request;
    request.set_name(args[1].toStdString());
    request.set_verbosity_level(parser->verbosityLevel());

    for (const auto& role : parser->values(service_option))
    {
        auto* member = request.add_members();
        member->set_role(role.toStdString());
    }

    for (const auto& spec : parser->values(instance_option))
    {
        const auto fields = spec.split(':');
        if (fields.size() < 1 || fields[0].isEmpty())
        {
            cerr << fmt::format("Invalid --instance spec \"{}\"; expected "
                                "role:image:cloud-init-file:cores:mem:disk.\n",
                                spec.toStdString());
            return parser->returnCodeFrom(ParseCode::CommandLineError);
        }

        auto* member = request.add_members();
        member->set_role(fields[0].toStdString());
        if (fields.size() > 1 && !fields[1].isEmpty())
            member->set_image(fields[1].toStdString());
        if (fields.size() > 2 && !fields[2].isEmpty())
        {
            QFile file{fields[2]};
            if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
            {
                cerr << fmt::format("Could not read cloud-init file \"{}\".\n",
                                    fields[2].toStdString());
                return parser->returnCodeFrom(ParseCode::CommandLineError);
            }
            member->set_cloud_init_user_data(QTextStream{&file}.readAll().toStdString());
        }
        if (fields.size() > 3 && !fields[3].isEmpty())
            member->set_num_cores(fields[3].toInt());
        if (fields.size() > 4 && !fields[4].isEmpty())
            member->set_mem_size(fields[4].toStdString());
        if (fields.size() > 5 && !fields[5].isEmpty())
            member->set_disk_space(fields[5].toStdString());
    }

    AnimatedSpinner spinner{cout};
    auto on_success = [this, &spinner](IntentCreateReply& reply) -> ReturnCodeVariant {
        spinner.stop();
        cout << reply.reply_message() << "\n";
        return ReturnCode::Ok;
    };
    auto on_failure = [this, &spinner](grpc::Status& status,
                                       IntentCreateReply& reply) -> ReturnCodeVariant {
        spinner.stop();
        return standard_failure_handler_for(name(), cerr, status, reply.reply_message());
    };

    spinner.start("Creating intent " + request.name());
    return dispatch(&RpcMethod::intent_create, request, on_success, on_failure);
}

mp::ReturnCodeVariant cmd::Intent::run_list(ArgParser* parser)
{
    IntentListRequest request;
    request.set_verbosity_level(parser->verbosityLevel());

    auto on_success = [this](IntentListReply& reply) -> ReturnCodeVariant {
        if (reply.intents().empty())
        {
            cout << "No intents found.\n";
            return ReturnCode::Ok;
        }

        for (const auto& intent : reply.intents())
        {
            cout << intent.name() << "\n";
            for (const auto& member : intent.members())
                cout << fmt::format("  {} ({}): {}\n",
                                    member.role(),
                                    member.instance_name(),
                                    instance_status_name(member.instance_status().status()));
        }
        return ReturnCode::Ok;
    };
    auto on_failure = [this](grpc::Status& status, IntentListReply&) -> ReturnCodeVariant {
        return standard_failure_handler_for(name(), cerr, status);
    };

    return dispatch(&RpcMethod::intent_list, request, on_success, on_failure);
}

mp::ReturnCodeVariant cmd::Intent::run_info(ArgParser* parser)
{
    const auto args = parser->positionalArguments();
    if (args.size() < 2)
    {
        cerr << "Please provide the name of the intent.\n";
        return parser->returnCodeFrom(ParseCode::CommandLineError);
    }

    IntentInfoRequest request;
    request.set_name(args[1].toStdString());
    request.set_verbosity_level(parser->verbosityLevel());

    auto on_success = [this](IntentInfoReply& reply) -> ReturnCodeVariant {
        const auto& intent = reply.intent();
        cout << fmt::format("Name:    {}\n", intent.name());
        cout << "Members:\n";
        for (const auto& member : intent.members())
            cout << fmt::format("  {} ({}): {}\n",
                                member.role(),
                                member.instance_name(),
                                instance_status_name(member.instance_status().status()));
        return ReturnCode::Ok;
    };
    auto on_failure = [this](grpc::Status& status, IntentInfoReply&) -> ReturnCodeVariant {
        return standard_failure_handler_for(name(), cerr, status);
    };

    return dispatch(&RpcMethod::intent_info, request, on_success, on_failure);
}

mp::ReturnCodeVariant cmd::Intent::run_delete(ArgParser* parser)
{
    const auto args = parser->positionalArguments();
    if (args.size() < 2)
    {
        cerr << "Please provide the name of the intent.\n";
        return parser->returnCodeFrom(ParseCode::CommandLineError);
    }

    IntentDeleteRequest request;
    request.set_name(args[1].toStdString());
    request.set_purge(parser->isSet(purge_option));
    request.set_verbosity_level(parser->verbosityLevel());

    auto on_success = [this](IntentDeleteReply& reply) -> ReturnCodeVariant {
        cout << reply.reply_message() << "\n";
        return ReturnCode::Ok;
    };
    auto on_failure = [this](grpc::Status& status, IntentDeleteReply& reply) -> ReturnCodeVariant {
        return standard_failure_handler_for(name(), cerr, status, reply.reply_message());
    };

    return dispatch(&RpcMethod::intent_delete, request, on_success, on_failure);
}
