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
#include "tls_fingerprint.h"

#include <multipass/cli/client_common.h>
#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/ssl_cert_provider.h>
#include <multipass/standard_paths.h>
#include <multipass/utils.h>

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QFile>

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

QString default_https_cert_dir()
{
    const auto data = MP_STDPATHS.writableLocation(mp::StandardPaths::GenericDataLocation);
    return QDir{data + "/hyperpass-api/https"}.path();
}

/** Prefer AtomOS shared daemon certs when present (same pin as matcher/storage). */
bool try_load_atomos_certs(mp::api::ApiConfig& config)
{
    static constexpr auto atomos_cert = "/etc/elemento/certs/atomos.crt";
    static constexpr auto atomos_key = "/etc/elemento/certs/atomos.key";
    if (!QFile::exists(QString::fromUtf8(atomos_cert)) || !QFile::exists(QString::fromUtf8(atomos_key)))
        return false;

    config.cert_file = atomos_cert;
    config.key_file = atomos_key;
    config.cert_pem = MP_UTILS.contents_of(QString::fromUtf8(atomos_cert));
    config.key_pem = MP_UTILS.contents_of(QString::fromUtf8(atomos_key));
    return true;
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

void mp::api::prepare_tls(ApiConfig& config)
{
    if (!config.use_https)
        return;

#ifndef CPPHTTPLIB_OPENSSL_SUPPORT
    throw std::runtime_error("HTTPS requested but cpp-httplib was built without OpenSSL support");
#else
    if (!config.cert_file.empty() || !config.key_file.empty())
    {
        if (config.cert_file.empty() || config.key_file.empty())
        {
            throw std::runtime_error(
                "HTTPS requires both --cert / HYPERPASS_API_CERT and --key / HYPERPASS_API_KEY");
        }
        config.cert_pem = MP_UTILS.contents_of(QString::fromStdString(config.cert_file));
        config.key_pem = MP_UTILS.contents_of(QString::fromStdString(config.key_file));
    }
    else if (try_load_atomos_certs(config))
    {
        // Co-located AtomOS install: reuse atomos.crt/key so Electros TOFU pin covers the VM API.
    }
    else
    {
        const QDir cert_dir{default_https_cert_dir()};
        if (!cert_dir.exists())
            QDir().mkpath(cert_dir.path());

        // Empty server name => local self-signed pair under our data dir (do not use
        // the gRPC daemon root-cert path that a non-empty name would trigger).
        mp::SSLCertProvider provider{cert_dir.path()};
        config.cert_pem = provider.PEM_certificate();
        config.key_pem = provider.PEM_signing_key();
    }

    config.tls_fingerprint = fingerprint_from_pem(config.cert_pem);
#endif
}

mp::api::ApiConfig mp::api::parse_config()
{
    QCommandLineParser parser;
    parser.setApplicationDescription("Hyperpass REST API sidecar");
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption listen_option{
        "listen",
        "HTTP(S) listen address (host:port); temporary default is matcher port 7777",
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
    QCommandLineOption https_option{
        "https",
        "Serve HTTPS (default; AtomOS/Electros-compatible). Auto-generates a self-signed cert "
        "unless --cert/--key are set"};
    QCommandLineOption http_option{
        "http",
        "Serve plain HTTP instead of HTTPS (local debugging only; breaks Electros fingerprinting)"};
    QCommandLineOption cert_option{"cert", "TLS certificate PEM file", "path"};
    QCommandLineOption key_option{"key", "TLS private key PEM file", "path"};

    parser.addOption(listen_option);
    parser.addOption(daemon_option);
    parser.addOption(token_option);
    parser.addOption(insecure_option);
    parser.addOption(no_multipass_option);
    parser.addOption(multipass_option);
    parser.addOption(verbosity_option);
    parser.addOption(https_option);
    parser.addOption(http_option);
    parser.addOption(cert_option);
    parser.addOption(key_option);
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

    const auto cert_env = qgetenv(mp::api_cert_env_var);
    const auto key_env = qgetenv(mp::api_key_env_var);
    if (parser.isSet(cert_option))
        config.cert_file = parser.value(cert_option).toStdString();
    else if (!cert_env.isEmpty())
        config.cert_file = cert_env.toStdString();
    if (parser.isSet(key_option))
        config.key_file = parser.value(key_option).toStdString();
    else if (!key_env.isEmpty())
        config.key_file = key_env.toStdString();

    // HTTPS is the AtomOS/Electros default. --http opts out; --https / certs force it on.
    if (parser.isSet(http_option) && !parser.isSet(https_option) && config.cert_file.empty() &&
        config.key_file.empty())
        config.use_https = false;
    else
        config.use_https = true;

    prepare_tls(config);

    return config;
}
