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

#include "multipass_discovery.h"

#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/utils.h>

#include <QDir>
#include <QFileInfo>

#include <cstdlib>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "multipass-discovery";

bool file_exists(const QString& path)
{
    return QFileInfo::exists(path);
}

std::string read_file(const QString& path)
{
    return mp::utils::contents_of(path);
}

QString multipass_root_cert_path()
{
#if defined(MULTIPASS_PLATFORM_WINDOWS)
    const auto program_data = qEnvironmentVariable("PROGRAMDATA", "C:\\ProgramData");
    return QDir(program_data).filePath("Multipass/data/multipassd/multipass_root_cert.pem");
#elif defined(MULTIPASS_PLATFORM_APPLE)
    return QStringLiteral("/usr/local/etc/multipassd/multipass_root_cert.pem");
#else
    const auto snap_common = qEnvironmentVariable("SNAP_COMMON");
    if (!snap_common.isEmpty())
    {
        const auto snap_path =
            QDir(snap_common).filePath("data/multipassd/multipass_root_cert.pem");
        if (file_exists(snap_path))
            return snap_path;
    }
    const auto snap_host =
        QStringLiteral("/var/snap/multipass/common/data/multipassd/multipass_root_cert.pem");
    if (file_exists(snap_host))
        return snap_host;
    return QStringLiteral("/usr/local/etc/multipassd/multipass_root_cert.pem");
#endif
}

QString multipass_client_cert_dir()
{
#if defined(MULTIPASS_PLATFORM_WINDOWS)
    const auto appdata = qEnvironmentVariable("APPDATA");
    return QDir(appdata).filePath("multipass-client-certificate");
#elif defined(MULTIPASS_PLATFORM_APPLE)
    const auto home = qEnvironmentVariable("HOME");
    return QDir(home).filePath("Library/Application Support/multipass-client-certificate");
#else
    const auto xdg = qEnvironmentVariable("XDG_DATA_HOME");
    if (!xdg.isEmpty())
        return QDir(xdg).filePath("multipass-client-certificate");
    const auto home = qEnvironmentVariable("HOME");
    return QDir(home).filePath(".local/share/multipass-client-certificate");
#endif
}

bool address_looks_available(const std::string& address)
{
    constexpr std::string_view unix_prefix = "unix:";
    if (address.rfind(unix_prefix, 0) == 0)
        return file_exists(QString::fromStdString(address.substr(unix_prefix.size())));
    // TCP: allow the connection attempt.
    return true;
}
} // namespace

std::string mp::api::default_multipass_server_address()
{
#if defined(MULTIPASS_PLATFORM_WINDOWS)
    return "localhost:50051";
#elif defined(MULTIPASS_PLATFORM_APPLE)
    return "unix:/var/run/multipass_socket";
#else
    auto unix_if_exists = [](const QString& socket_path) -> std::string {
        if (file_exists(socket_path))
            return fmt::format("unix:{}", socket_path.toStdString());
        return {};
    };

    const auto snap_common = qEnvironmentVariable("SNAP_COMMON");
    if (!snap_common.isEmpty())
    {
        if (auto addr = unix_if_exists(QDir(snap_common).filePath("multipass_socket"));
            !addr.empty())
            return addr;
    }
    if (auto addr =
            unix_if_exists(QStringLiteral("/var/snap/multipass/common/multipass_socket"));
        !addr.empty())
        return addr;
    return "unix:/run/multipass_socket";
#endif
}

std::optional<mp::api::MultipassConnection> mp::api::discover_multipass_connection(
    const std::string& address_override)
{
    try
    {
        MultipassConnection conn;
        conn.address =
            address_override.empty() ? default_multipass_server_address() : address_override;

        if (!address_looks_available(conn.address))
        {
            mpl::log_message(mpl::Level::warning,
                             category,
                             fmt::format("Multipass socket/address not available: {}",
                                         conn.address));
            return std::nullopt;
        }

        const auto root_path = multipass_root_cert_path();
        if (!file_exists(root_path))
        {
            mpl::log_message(
                mpl::Level::warning,
                category,
                fmt::format("Multipass root CA missing: {}", root_path.toStdString()));
            return std::nullopt;
        }

        const auto cert_dir = multipass_client_cert_dir();
        const auto cert_path = QDir(cert_dir).filePath("multipass_cert.pem");
        const auto key_path = QDir(cert_dir).filePath("multipass_cert_key.pem");
        if (!file_exists(cert_path) || !file_exists(key_path))
        {
            mpl::log_message(mpl::Level::warning,
                             category,
                             fmt::format("Multipass client certificates missing under {}",
                                         cert_dir.toStdString()));
            return std::nullopt;
        }

        conn.root_cert_pem = read_file(root_path);
        conn.client_cert_pem = read_file(cert_path);
        conn.client_key_pem = read_file(key_path);

        mpl::log_message(
            mpl::Level::info,
            category,
            fmt::format("Discovered Multipass at {} (certs under {})",
                        conn.address,
                        cert_dir.toStdString()));
        return conn;
    }
    catch (const std::exception& e)
    {
        mpl::log_message(mpl::Level::warning,
                         category,
                         fmt::format("Failed to discover Multipass connection: {}", e.what()));
        return std::nullopt;
    }
}

std::shared_ptr<grpc::Channel> mp::api::make_channel_with_pems(const std::string& server_address,
                                                               const std::string& root_cert_pem,
                                                               const std::string& client_cert_pem,
                                                               const std::string& client_key_pem)
{
    grpc::SslCredentialsOptions opts;
    opts.pem_root_certs = root_cert_pem;
    opts.pem_cert_chain = client_cert_pem;
    opts.pem_private_key = client_key_pem;

    grpc::ChannelArguments channel_args;
    channel_args.SetString(GRPC_ARG_DEFAULT_AUTHORITY, "localhost");
    return grpc::CreateCustomChannel(server_address,
                                     grpc::SslCredentials(opts),
                                     channel_args);
}
