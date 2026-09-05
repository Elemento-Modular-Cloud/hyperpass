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

#include "resources.h"
#include "common_cli.h"

#include <multipass/cli/argparser.h>
#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/memory_size.h>

namespace mp = multipass;
namespace cmd = multipass::cmd;

namespace
{
std::string bytes_hr(uint64_t bytes)
{
    return mp::MemorySize::from_bytes(static_cast<long long>(bytes)).human_readable();
}
} // namespace

mp::ReturnCodeVariant cmd::Resources::run(mp::ArgParser* parser)
{
    auto ret = parse_args(parser);
    if (ret != ParseCode::Ok)
        return parser->returnCodeFrom(ret);

    auto on_success = [this](mp::DaemonInfoReply& reply) -> ReturnCodeVariant {
        const auto host = reply.memory();
        const auto used_host = reply.memory_used_host();
        const auto host_pct = host ? (100.0 * used_host / host) : 0.0;
        const auto cpu_pct = reply.cpu_usage_permille() / 10.0;

        cout << "Host resource pool\n";
        cout << fmt::format("  RAM total:     {}\n", bytes_hr(host));
        cout << fmt::format("  RAM reserve:   {}\n", bytes_hr(reply.memory_reserved()));
        cout << fmt::format("  RAM claimed:   {}  (scheduler)\n", bytes_hr(reply.memory_claimed()));
        cout << fmt::format("  RAM available: {}\n", bytes_hr(reply.memory_available()));
        cout << fmt::format("  RAM used (OS): {} ({:.0f}%)\n", bytes_hr(used_host), host_pct);
        cout << fmt::format("  CPUs:          {} host, {} claimed\n",
                            reply.cpus(),
                            reply.cpus_claimed());
        cout << fmt::format("  CPU usage:     {:.1f}%\n", cpu_pct);

        if (reply.claims_size() > 0)
        {
            cout << "\nClaims\n";
            cout << fmt::format("  {:<24} {:<8} {:>10} {:>6}\n", "NAME", "KIND", "RAM", "CPUS");
            for (const auto& claim : reply.claims())
            {
                cout << fmt::format("  {:<24} {:<8} {:>10} {:>6}\n",
                                    claim.name(),
                                    claim.kind(),
                                    bytes_hr(claim.memory_bytes()),
                                    claim.cpus());
            }
        }
        return ReturnCode::Ok;
    };

    auto on_failure = [this](grpc::Status& status) -> ReturnCodeVariant {
        return standard_failure_handler_for(name(), cerr, status);
    };

    DaemonInfoRequest request;
    request.set_verbosity_level(parser->verbosityLevel());
    return dispatch_with_deadline(&RpcMethod::daemon_info,
                                  request,
                                  on_success,
                                  on_failure,
                                  mp::quick_rpc_deadline);
}

std::string cmd::Resources::name() const
{
    return "resources";
}

QString cmd::Resources::short_help() const
{
    return QStringLiteral("Show host RAM and CPU reservations");
}

QString cmd::Resources::description() const
{
    return QStringLiteral(
        "Display Electros LaunchPad scheduler reservations versus live host pressure.");
}

mp::ParseCode cmd::Resources::parse_args(mp::ArgParser* parser)
{
    return parser->commandParse(this);
}
