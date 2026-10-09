/*
 * Copyright (C) Canonical, Ltd.
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

#include "client.h"
#include "cmd/alias.h"
#include "cmd/aliases.h"
#include "cmd/authenticate.h"
#include "cmd/disable_zones.h"
#include "cmd/enable_zones.h"
#include "cmd/get.h"
#include "cmd/help.h"
#include "cmd/intent.h"
#include "cmd/llm.h"
#include "cmd/networks.h"
#include "cmd/port_forward.h"
#include "cmd/prefer.h"
#include "cmd/remote_settings_handler.h"
#include "cmd/resources.h"
#include "cmd/services.h"
#include "cmd/set.h"
#include "cmd/unalias.h"
#include "cmd/version.h"
#include "cmd/vm.h"
#include "cmd/wait_ready.h"
#include "cmd/zones.h"

#include <multipass/cli/argparser.h>
#include <multipass/cli/client_common.h>
#include <multipass/cli/client_platform.h>
#include <multipass/constants.h>
#include <multipass/logging/log.h>
#include <multipass/platform.h>
#include <multipass/settings/settings.h>
#include <multipass/top_catch_all.h>

#include <scope_guard.hpp>

#include <algorithm>
#include <memory>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
auto make_handler_unregisterer(mp::SettingsHandler* handler)
{
    return sg::make_scope_guard([handler]() noexcept {
        mp::top_catch_all("client", [handler] {
            MP_SETTINGS.unregister_handler(handler); // trust me clang-format
        });
    });
}
} // namespace

mp::Client::Client(ClientConfig& config)
    : stub{mp::Rpc::NewStub(
          mp::client::make_channel(config.server_address, *config.cert_provider))},
      term{config.term},
      aliases{AliasDict::load_file(config.term)}
{
    add_command<cmd::Alias>(aliases);
    add_command<cmd::Aliases>(aliases);
    add_command<cmd::Authenticate>();
    add_command<cmd::Get>();
    add_command<cmd::Help>();
    add_command<cmd::Intent>();
    add_command<cmd::Llm>();
    add_command<cmd::Networks>();
    add_command<cmd::PortForward>();
    add_command<cmd::Prefer>(aliases);
    add_command<cmd::Resources>();
    add_command<cmd::Services>();
    add_command<cmd::Set>();
    add_command<cmd::Unalias>(aliases);
    add_command<cmd::Version>();
    add_command<cmd::Vm>(aliases);
    add_command<cmd::WaitReady>();
    add_command<cmd::DisableZones>();
    add_command<cmd::EnableZones>();
    add_command<cmd::Zones>();

    sort_commands();

    MP_CLIENT_PLATFORM.enable_ansi_escape_chars();
}

void mp::Client::sort_commands()
{
    auto name_sort = [](cmd::Command::UPtr& a, cmd::Command::UPtr& b) {
        return a->name() < b->name();
    };
    std::sort(commands.begin(), commands.end(), name_sort);
}

mp::ReturnCodeVariant mp::Client::run(const QStringList& arguments)
{
    QString description(
        QStringLiteral(
            "Create, control and connect to VMs, LLMs, and services.\n\n"
            "Workload groups: `%1 vm`, `%1 llm`, `%1 services`.\n"
            "Shared: settings (`get`/`set`), networks, zones, intents, aliases.")
            .arg(QLatin1String(mp::client_name)));

    ArgParser parser(arguments, commands, term->cout(), term->cerr());
    parser.setApplicationDescription(description);

    mp::ReturnCodeVariant ret = mp::ReturnCode::Ok;
    ParseCode parse_status = parser.parse(aliases);

    auto verbosity =
        parser.verbosityLevel(); // try to respect requested verbosity, even if parsing failed
    if (!mpl::get_logger())
        mp::client::set_logger(mpl::level_from(verbosity));

    {
        auto daemon_settings_prefix = QString{daemon_settings_root} + ".";
        auto* handler = MP_SETTINGS.register_handler(
            std::make_unique<RemoteSettingsHandler>(std::move(daemon_settings_prefix),
                                                    *stub,
                                                    term,
                                                    verbosity));
        auto handler_unregisterer =
            make_handler_unregisterer(handler); // remove handler before its dependencies expire

        try
        {
            ret = parse_status == ParseCode::Ok ? parser.chosenCommand()->run(&parser)
                                                : parser.returnCodeFrom(parse_status);
        }
        catch (const RemoteHandlerException& e)
        {
            ret = mp::cmd::standard_failure_handler_for(parser.chosenCommand()->name(),
                                                        term->cerr(),
                                                        e.get_status());
        }
    }

    mp::client::post_setup();

    return ret;
}
