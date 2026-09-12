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

#include "migrate.h"

#include "animated_spinner.h"
#include "common_cli.h"

#include <multipass/cli/argparser.h>
#include <multipass/format.h>

namespace mp = multipass;
namespace cmd = multipass::cmd;

namespace
{
const QCommandLineOption to_option{"to",
                                   "Target host, reachable over ssh, with elp already "
                                   "installed and its daemon running (\"user@host\").",
                                   "user@host"};
const QCommandLineOption copy_option{
    "copy", "Keep the source instance(s)/session(s) instead of deleting them once migrated."};
} // namespace

mp::ReturnCodeVariant cmd::Migrate::run(ArgParser* parser)
{
    auto parsed = parse_args(parser);
    if (parsed != ParseCode::Ok)
        return parser->returnCodeFrom(parsed);

    MigrateRequest request;
    request.set_name(instance_name);
    request.set_target(target.toStdString());
    request.set_copy(copy);
    request.set_verbosity_level(parser->verbosityLevel());

    AnimatedSpinner spinner{cout};
    spinner.start(fmt::format("Migrating \"{}\" to {}", instance_name, target.toStdString()));

    auto on_success = [this, &spinner](MigrateReply& reply) -> ReturnCodeVariant {
        spinner.stop();
        cout << reply.reply_message() << "\n";
        return ReturnCode::Ok;
    };
    auto on_failure = [this, &spinner](grpc::Status& status, MigrateReply& reply) -> ReturnCodeVariant {
        spinner.stop();
        return standard_failure_handler_for(name(), cerr, status, reply.reply_message());
    };
    auto streaming = [this, &spinner](const MigrateReply& reply, auto*) {
        if (!reply.log_line().empty())
        {
            spinner.stop();
            cout << reply.log_line() << "\n";
            spinner.start(fmt::format("Migrating \"{}\" to {}", instance_name, target.toStdString()));
        }
    };

    return dispatch(&RpcMethod::migrate, request, on_success, on_failure, streaming);
}

std::string cmd::Migrate::name() const
{
    return "migrate";
}

QString cmd::Migrate::short_help() const
{
    return QStringLiteral("Migrate an instance or intent to another elp host");
}

QString cmd::Migrate::description() const
{
    return QStringLiteral(
        "Migrate a single instance or a whole intent to another host running elpd, "
        "reachable over ssh. The instance(s) are stopped, redefined on the target with "
        "the same image/cloud-init (or, for an LLM intent member, reloaded there), and "
        "any mounts are synced across; the source is then deleted unless --copy is given.\n\n"
        "  elp migrate my-instance --to user@host\n"
        "  elp migrate my-intent --to user@host --copy");
}

mp::ParseCode cmd::Migrate::parse_args(ArgParser* parser)
{
    parser->addPositionalArgument("name", "Name of the instance or intent to migrate", "<name>");
    parser->addOption(to_option);
    parser->addOption(copy_option);

    const auto status = parser->commandParse(this);
    if (status != ParseCode::Ok)
        return status;

    const auto args = parser->positionalArguments();
    if (args.empty())
    {
        cerr << "Please provide the name of an instance or intent to migrate.\n";
        return ParseCode::CommandLineError;
    }
    instance_name = args[0].toStdString();

    if (!parser->isSet(to_option))
    {
        cerr << "Please specify a target with --to user@host.\n";
        return ParseCode::CommandLineError;
    }
    target = parser->value(to_option);
    copy = parser->isSet(copy_option);

    return ParseCode::Ok;
}
