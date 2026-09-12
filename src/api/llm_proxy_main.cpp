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
#include "grpc_backend.h"
#include "server.h"

#include <multipass/cli/client_common.h>
#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/top_catch_all.h>

#include <openssl/crypto.h>

#include <QCoreApplication>

#include <atomic>
#include <csignal>
#include <memory>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
std::atomic<mp::api::ApiServer*> g_server{nullptr};

void handle_signal(int)
{
    if (auto* server = g_server.load())
        server->stop();
}

int main_impl(int argc, char* argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(mp::llm_proxy_name);

    auto config = mp::api::parse_config(mp::api::ServerRole::llm_proxy);

    mp::client::set_logger(config.verbosity_level);
    mp::client::register_global_settings_handlers();

    auto cert_provider = mp::client::get_cert_provider();
    auto channel = mp::client::make_channel(config.daemon_address, *cert_provider);
    auto elp_backend = std::make_shared<mp::api::GrpcBackend>(std::move(channel));

    mp::api::ApiServer server{std::move(config), std::move(elp_backend)};
    g_server.store(&server);

    std::signal(SIGINT, handle_signal);
#ifndef MULTIPASS_PLATFORM_WINDOWS
    std::signal(SIGTERM, handle_signal);
#endif

    const auto ok = server.listen();
    g_server.store(nullptr);

    if (!ok)
    {
        mpl::log_message(mpl::Level::error, "llm-proxy", "failed to bind/listen HTTP server");
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
} // namespace

int main(int argc, char* argv[])
{
    GOOGLE_PROTOBUF_VERIFY_VERSION;

    if (OPENSSL_init_crypto(OPENSSL_INIT_NO_ATEXIT, nullptr) != 1)
        return EXIT_FAILURE;

    return mp::top_catch_all("llm-proxy",
                             /* fallback_return = */ EXIT_FAILURE,
                             main_impl,
                             argc,
                             argv);
}
