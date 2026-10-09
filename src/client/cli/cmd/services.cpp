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

#include "services.h"
#include "common_cli.h"

#include <multipass/cli/argparser.h>
#include <multipass/cli/cli_style.h>
#include <multipass/cli/format_utils.h>
#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/ssh/plain_ssh_session.h>
#include <multipass/utils.h>

#include <ssh/ssh_client_key_provider.h>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>

#include <chrono>
#include <functional>

namespace mp = multipass;
namespace cmd = multipass::cmd;
namespace style = multipass::cli_style;

namespace
{
constexpr auto default_healthcheck = "/opt/elemento/bin/healthcheck";
constexpr auto default_service_info = "/opt/elemento/bin/service-info";

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

/// Match GUI guestPrivilegedCommand: sudo -n when passwordless sudo works.
std::string guest_privileged_command(const std::string& path)
{
    std::string escaped;
    for (char c : path)
    {
        if (c == '\'')
            escaped += "'\\''";
        else
            escaped.push_back(c);
    }
    return fmt::format(
        "if sudo -n true >/dev/null 2>&1; then sudo -n -- '{}'; else '{}'; fi",
        escaped,
        escaped);
}

struct GuestCmdResult
{
    int exit_code{1};
    std::string stdout_text;
    std::string stderr_text;
};

GuestCmdResult run_on_guest(const mp::SSHInfo& ssh_info, const std::string& cmd_line)
{
    mp::PlainSSHSession session{ssh_info.host(),
                                static_cast<int>(ssh_info.port()),
                                ssh_info.username(),
                                mp::SSHClientKeyProvider{ssh_info.priv_key_base64()}};
    auto proc = session.exec(cmd_line);
    GuestCmdResult result;
    result.stdout_text = proc->read_std_output();
    result.stderr_text = proc->read_std_error();
    result.exit_code = proc->exit_code(std::chrono::seconds{30});
    return result;
}

} // namespace

mp::ParseCode cmd::Services::parse_args(mp::ArgParser* parser)
{
    parser->addPositionalArgument("subcommand",
                                  "list | healthcheck | info",
                                  "<subcommand>");
    parser->addPositionalArgument("instance",
                                  "Service instance name (for healthcheck/info)",
                                  "[<instance>]");
    auto status = parser->commandParse(this);
    if (status != ParseCode::Ok)
        return status;

    const auto args = parser->positionalArguments();
    if (args.isEmpty())
    {
        cerr << "Missing services subcommand. Try `" << mp::client_name << " services -h`.\n";
        return ParseCode::CommandLineError;
    }
    subcommand = args.at(0).toLower();
    if (args.size() > 1)
        instance_name = args.at(1);
    return ParseCode::Ok;
}

mp::ReturnCodeVariant cmd::Services::run(mp::ArgParser* parser)
{
    auto status = parse_args(parser);
    if (status != ParseCode::Ok)
        return parser->returnCodeFrom(status);

    if (subcommand == "list" || subcommand == "ls")
        return run_list(parser);
    if (subcommand == "healthcheck" || subcommand == "health")
        return run_healthcheck(parser);
    if (subcommand == "info" || subcommand == "service-info")
        return run_info(parser);

    cerr << "Unknown services subcommand '" << qUtf8Printable(subcommand) << "'. "
         << "Try `" << mp::client_name << " services -h`.\n";
    return ReturnCode::CommandLineError;
}

mp::ReturnCodeVariant cmd::Services::with_guest(
    mp::ArgParser* parser,
    const std::function<ReturnCodeVariant(const SSHInfo&)>& body)
{
    SSHInfoRequest request;
    request.set_verbosity_level(parser->verbosityLevel());
    request.add_instance_name(instance_name.toStdString());

    auto on_success = [&](SSHInfoReply& reply) -> ReturnCodeVariant {
        if (reply.ssh_info().empty())
        {
            cerr << "No SSH info for instance '" << qUtf8Printable(instance_name) << "'\n";
            return ReturnCode::CommandFail;
        }
        return body(reply.ssh_info().begin()->second);
    };

    return dispatch_with_deadline(&RpcMethod::ssh_info,
                                  request,
                                  on_success,
                                  [&](grpc::Status& s) { return fail(cerr, s, name()); },
                                  mp::quick_rpc_deadline);
}

mp::ReturnCodeVariant cmd::Services::run_list(mp::ArgParser* parser)
{
    const auto as_json = parser->jsonOutput() || style::json_enabled();
    ListRequest request;
    request.set_verbosity_level(parser->verbosityLevel());
    request.set_request_ipv4(true);
    request.set_instance_kind("service");

    auto on_success = [this, as_json](ListReply& reply) -> ReturnCodeVariant {
        if (!reply.has_instance_list() || reply.instance_list().instances().empty())
        {
            if (as_json)
            {
                QJsonObject root;
                root.insert("services", QJsonArray{});
                style::print_json(cout, root);
            }
            else
                style::print_info(cout, "No service deployments found.");
            return ReturnCode::Ok;
        }

        QJsonArray json_rows;
        style::Table table;
        table.columns = {{"NAME"}, {"SERVICE"}, {"STATE"}, {"IMAGE"}, {"IPV4"}};

        for (const auto& instance : reply.instance_list().instances())
        {
            const auto state = mp::format::status_string_for(instance.instance_status());
            const auto ip = instance.ipv4_size() ? instance.ipv4(0) : std::string{"-"};
            auto image = instance.current_release().empty()
                             ? std::string{"-"}
                             : fmt::format("{} {}", instance.os(), instance.current_release());
            image = mp::utils::trim(std::move(image));
            if (as_json)
            {
                QJsonObject o;
                o.insert("name", QString::fromStdString(instance.name()));
                o.insert("service_id", QString::fromStdString(instance.service_id()));
                o.insert("state", QString::fromStdString(state));
                o.insert("image", QString::fromStdString(image));
                o.insert("ipv4", QString::fromStdString(ip));
                json_rows.push_back(o);
            }
            else
            {
                table.rows.push_back({instance.name(),
                                      instance.service_id(),
                                      style::paint_status(state),
                                      image,
                                      ip});
            }
        }

        if (as_json)
        {
            QJsonObject root;
            root.insert("services", json_rows);
            style::print_json(cout, root);
            return ReturnCode::Ok;
        }
        if (table.rows.empty())
        {
            style::print_info(cout, "No service deployments found.");
            return ReturnCode::Ok;
        }
        style::print_table(cout, table);
        return ReturnCode::Ok;
    };

    return dispatch_with_deadline(&RpcMethod::list,
                                  request,
                                  on_success,
                                  [&](grpc::Status& s) { return fail(cerr, s, name()); },
                                  mp::quick_rpc_deadline);
}

mp::ReturnCodeVariant cmd::Services::run_healthcheck(mp::ArgParser* parser)
{
    if (instance_name.isEmpty())
    {
        cerr << "Usage: " << mp::client_name << " services healthcheck <instance>\n";
        return ReturnCode::CommandLineError;
    }
    const auto as_json = parser->jsonOutput() || style::json_enabled();

    return with_guest(parser, [&](const SSHInfo& ssh_info) -> ReturnCodeVariant {
        try
        {
            const auto result =
                run_on_guest(ssh_info, guest_privileged_command(default_healthcheck));
            const bool healthy = result.exit_code == 0;
            auto detail = healthy ? std::string{}
                                  : (result.stderr_text.empty() ? result.stdout_text
                                                                : result.stderr_text);
            detail = mp::utils::trim(std::move(detail));
            if (as_json)
            {
                QJsonObject o;
                o.insert("instance", instance_name);
                o.insert("healthy", healthy);
                o.insert("exit_code", result.exit_code);
                o.insert("detail", QString::fromStdString(detail));
                style::print_json(cout, o);
            }
            else if (healthy)
                style::print_ok(cout, fmt::format("{}: healthy", instance_name));
            else
                style::print_err(
                    cout,
                    fmt::format("{}: unhealthy (exit {}){}",
                                instance_name,
                                result.exit_code,
                                detail.empty() ? "" : fmt::format(" — {}", detail)));
            return healthy ? ReturnCode::Ok : ReturnCode::CommandFail;
        }
        catch (const std::exception& e)
        {
            if (as_json)
            {
                QJsonObject o;
                o.insert("instance", instance_name);
                o.insert("healthy", false);
                o.insert("exit_code", -1);
                o.insert("detail", QString::fromUtf8(e.what()));
                style::print_json(cout, o);
            }
            else
                style::print_err(cout,
                                 fmt::format("{}: unreachable — {}", instance_name, e.what()));
            return ReturnCode::CommandFail;
        }
    });
}

mp::ReturnCodeVariant cmd::Services::run_info(mp::ArgParser* parser)
{
    if (instance_name.isEmpty())
    {
        cerr << "Usage: " << mp::client_name << " services info <instance>\n";
        return ReturnCode::CommandLineError;
    }
    const auto as_json = parser->jsonOutput() || style::json_enabled();

    return with_guest(parser, [&](const SSHInfo& ssh_info) -> ReturnCodeVariant {
        try
        {
            const auto result =
                run_on_guest(ssh_info, guest_privileged_command(default_service_info));
            if (result.exit_code != 0)
            {
                auto err = result.stderr_text.empty()
                               ? fmt::format("service-info exited {}", result.exit_code)
                               : result.stderr_text;
                err = mp::utils::trim(std::move(err));
                if (as_json)
                {
                    QJsonObject o;
                    o.insert("ok", false);
                    o.insert("instance", instance_name);
                    o.insert("error", QString::fromStdString(err));
                    style::print_json(cout, o);
                }
                else
                    style::print_err(cout, fmt::format("{}: {}", instance_name, err));
                return ReturnCode::CommandFail;
            }

            QJsonParseError parse_error{};
            const auto doc =
                QJsonDocument::fromJson(QByteArray::fromStdString(result.stdout_text), &parse_error);
            if (parse_error.error != QJsonParseError::NoError || !doc.isObject())
            {
                if (as_json)
                {
                    cout << result.stdout_text;
                    if (!result.stdout_text.empty() && result.stdout_text.back() != '\n')
                        cout << '\n';
                }
                else
                {
                    style::print_warn(cout, "service-info returned non-JSON output:");
                    cout << result.stdout_text;
                    if (!result.stdout_text.empty() && result.stdout_text.back() != '\n')
                        cout << '\n';
                }
                return ReturnCode::Ok;
            }

            if (as_json)
            {
                style::print_json(cout, doc.object());
                return ReturnCode::Ok;
            }

            const auto obj = doc.object();
            style::Table meta;
            meta.columns = {{"FIELD"}, {"VALUE"}};
            meta.rows.push_back({"instance", instance_name.toStdString()});
            meta.rows.push_back({"service", obj.value("service").toString().toStdString()});
            meta.rows.push_back({"status", obj.value("status").toString().toStdString()});
            meta.rows.push_back(
                {"api_version", obj.value("api_version").toString().toStdString()});
            style::print_table(cout, meta);

            const auto endpoints = obj.value("endpoints").toObject();
            if (!endpoints.isEmpty())
            {
                cout << '\n' << style::paint(style::Tone::bold, "Endpoints") << '\n';
                style::Table t;
                t.columns = {{"NAME"}, {"URL"}};
                for (auto it = endpoints.begin(); it != endpoints.end(); ++it)
                    t.rows.push_back(
                        {it.key().toStdString(), it.value().toString().toStdString()});
                style::print_table(cout, t);
            }

            const auto credentials = obj.value("credentials").toObject();
            if (!credentials.isEmpty())
            {
                cout << '\n' << style::paint(style::Tone::bold, "Credentials") << '\n';
                style::Table t;
                t.columns = {{"KEY"}, {"VALUE"}};
                for (auto it = credentials.begin(); it != credentials.end(); ++it)
                {
                    QString value;
                    if (it.value().isArray())
                    {
                        QStringList parts;
                        for (const auto& v : it.value().toArray())
                            parts << v.toVariant().toString();
                        value = parts.join(", ");
                    }
                    else if (it.value().isObject())
                        value = QString::fromUtf8(
                            QJsonDocument{it.value().toObject()}.toJson(QJsonDocument::Compact));
                    else
                        value = it.value().toVariant().toString();
                    t.rows.push_back({it.key().toStdString(), value.toStdString()});
                }
                style::print_table(cout, t);
            }

            const auto backends = obj.value("backends").toArray();
            if (!backends.isEmpty())
            {
                cout << '\n' << style::paint(style::Tone::bold, "Backends") << '\n';
                for (const auto& b : backends)
                {
                    if (!b.isObject())
                        continue;
                    const auto bo = b.toObject();
                    QStringList parts;
                    for (auto it = bo.begin(); it != bo.end(); ++it)
                        parts << QStringLiteral("%1=%2").arg(it.key(),
                                                             it.value().toVariant().toString());
                    cout << "  " << parts.join("  ").toStdString() << '\n';
                }
            }
            return ReturnCode::Ok;
        }
        catch (const std::exception& e)
        {
            if (as_json)
            {
                QJsonObject o;
                o.insert("ok", false);
                o.insert("instance", instance_name);
                o.insert("error", QString::fromUtf8(e.what()));
                style::print_json(cout, o);
            }
            else
                style::print_err(cout,
                                 fmt::format("{}: unreachable — {}", instance_name, e.what()));
            return ReturnCode::CommandFail;
        }
    });
}

std::string cmd::Services::name() const
{
    return "services";
}

QString cmd::Services::short_help() const
{
    return QStringLiteral("List service deployments and query guest health/info");
}

QString cmd::Services::description() const
{
    return QStringLiteral(
        "Manage marketplace service deployments (VMs tagged with a service_id).\n\n"
        "Subcommands:\n"
        "  list                 List deployed service instances\n"
        "  healthcheck <name>   Run guest /opt/elemento/bin/healthcheck\n"
        "  info <name>          Run guest /opt/elemento/bin/service-info");
}
