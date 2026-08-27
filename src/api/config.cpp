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

#include "config.h"

#include <multipass/cli/client_common.h>
#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/utils.h>

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>

#include <stdexcept>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
mpl::Level to_logging_level(const QString& value)
{
    const auto value_lower = value.toLower();

    if (value_lower == "error")
        return mpl::Level::error;
    if (value_lower == "warning")
        return mpl::Level::warning;
    if (value_lower == "info")
        return mpl::Level::info;
    if (value_lower == "debug")
        return mpl::Level::debug;
    if (value_lower == "trace")
        return mpl::Level::trace;

    throw std::runtime_error(fmt::format("invalid logging verbosity: {}. "
                                         "Valid levels are: error|warning|info|debug|trace.",
                                         value));
}
} // namespace

void mp::api::parse_listen_address(const std::string& listen, std::string& host, int& port)
{
    const auto colon = listen.rfind(':');
    if (colon == std::string::npos || colon == 0 || colon + 1 >= listen.size())
        throw std::runtime_error(
            fmt::format("invalid listen address '{}'; expected host:port", listen));

    host = listen.substr(0, colon);
    try
    {
        port = std::stoi(listen.substr(colon + 1));
    }
    catch (const std::exception&)
    {
        throw std::runtime_error(
            fmt::format("invalid listen address '{}'; port is not a number", listen));
    }

    if (port <= 0 || port > 65535)
        throw std::runtime_error(
            fmt::format("invalid listen address '{}'; port out of range", listen));
}

mp::api::ApiConfig mp::api::parse_config()
{
    QCommandLineParser parser;
    parser.setApplicationDescription("Hyperpass REST API sidecar");
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption listen_option{"listen",
                                     "HTTP listen address (host:port)",
                                     "address",
                                     mp::default_api_listen};
    QCommandLineOption daemon_option{"daemon-address",
                                     "hyperpassd gRPC address (unix:… or host:port)",
                                     "address"};
    QCommandLineOption token_option{"api-token", "Bearer token required by REST clients", "token"};
    QCommandLineOption insecure_option{"insecure-no-auth",
                                       "Disable REST authentication (local development only)"};
    QCommandLineOption no_multipass_option{"no-multipass",
                                           "Do not discover or list stock Multipass instances"};
    QCommandLineOption multipass_option{"multipass-address",
                                        "Stock Multipass gRPC address (unix:… or host:port)",
                                        "address"};
    QCommandLineOption verbosity_option{{"V", "verbosity"},
                                        "Logging verbosity level",
                                        "error|warning|info|debug|trace"};

    parser.addOption(listen_option);
    parser.addOption(daemon_option);
    parser.addOption(token_option);
    parser.addOption(insecure_option);
    parser.addOption(no_multipass_option);
    parser.addOption(multipass_option);
    parser.addOption(verbosity_option);
    parser.process(*QCoreApplication::instance());

    ApiConfig config;

    const auto listen_env = qgetenv(mp::api_listen_env_var);
    if (parser.isSet(listen_option))
        config.listen_address = parser.value(listen_option).toStdString();
    else if (!listen_env.isEmpty())
        config.listen_address = listen_env.toStdString();
    else
        config.listen_address = mp::default_api_listen;

    // Validate early so misconfiguration fails fast.
    std::string host;
    int port = 0;
    parse_listen_address(config.listen_address, host, port);

    if (parser.isSet(daemon_option))
    {
        config.daemon_address = parser.value(daemon_option).toStdString();
        mp::utils::validate_server_address(config.daemon_address);
    }
    else
    {
        config.daemon_address = mp::client::get_server_address();
    }

    config.insecure_no_auth = parser.isSet(insecure_option);

    const auto token_env = qgetenv(mp::api_token_env_var);
    if (parser.isSet(token_option))
        config.api_token = parser.value(token_option).toStdString();
    else if (!token_env.isEmpty())
        config.api_token = token_env.toStdString();

    if (!config.insecure_no_auth && config.api_token.empty())
    {
        throw std::runtime_error(
            fmt::format("API token required: set --api-token / {} or pass --insecure-no-auth",
                        mp::api_token_env_var));
    }

    config.include_multipass = !parser.isSet(no_multipass_option);

    const auto multipass_env = qgetenv(mp::multipass_address_env_var);
    if (parser.isSet(multipass_option))
    {
        config.multipass_address = parser.value(multipass_option).toStdString();
        mp::utils::validate_server_address(config.multipass_address);
    }
    else if (!multipass_env.isEmpty())
    {
        config.multipass_address = multipass_env.toStdString();
        mp::utils::validate_server_address(config.multipass_address);
    }

    if (parser.isSet(verbosity_option))
        config.verbosity_level = to_logging_level(parser.value(verbosity_option));

    return config;
}
