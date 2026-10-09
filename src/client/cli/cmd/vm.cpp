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

#include "vm.h"

#include "clone.h"
#include "delete.h"
#include "exec.h"
#include "find.h"
#include "info.h"
#include "launch.h"
#include "list.h"
#include "migrate.h"
#include "mount.h"
#include "purge.h"
#include "recover.h"
#include "restart.h"
#include "restore.h"
#include "shell.h"
#include "snapshot.h"
#include "start.h"
#include "stop.h"
#include "suspend.h"
#include "transfer.h"
#include "umount.h"

#include <multipass/cli/argparser.h>
#include <multipass/constants.h>
#include <multipass/format.h>

#include <algorithm>

namespace mp = multipass;
namespace cmd = multipass::cmd;

namespace
{
template <typename T, typename... Args>
void add_sub(std::vector<cmd::Command::UPtr>& commands, Args&&... args)
{
    commands.push_back(std::make_unique<T>(std::forward<Args>(args)...));
}

void sort_by_name(std::vector<cmd::Command::UPtr>& commands)
{
    std::sort(commands.begin(), commands.end(), [](const auto& a, const auto& b) {
        return a->name() < b->name();
    });
}

bool has_non_option_token(const QStringList& args, int start_index)
{
    for (int i = start_index; i < args.size(); ++i)
    {
        if (!args[i].startsWith(QLatin1Char('-')))
            return true;
    }
    return false;
}
} // namespace

cmd::Vm::Vm(Rpc::StubInterface& stub, Terminal* term, AliasDict& aliases) : Command(stub, term)
{
    add_sub<Clone>(commands, stub, term);
    add_sub<Delete>(commands, stub, term, aliases);
    add_sub<Exec>(commands, stub, term, aliases);
    add_sub<Find>(commands, stub, term);
    add_sub<Info>(commands, stub, term);
    add_sub<Launch>(commands, stub, term, aliases);
    add_sub<List>(commands, stub, term);
    add_sub<Migrate>(commands, stub, term);
    add_sub<Mount>(commands, stub, term);
    add_sub<Purge>(commands, stub, term, aliases);
    add_sub<Recover>(commands, stub, term);
    add_sub<Restart>(commands, stub, term);
    add_sub<Restore>(commands, stub, term);
    add_sub<Shell>(commands, stub, term);
    add_sub<Snapshot>(commands, stub, term);
    add_sub<Start>(commands, stub, term);
    add_sub<Stop>(commands, stub, term);
    add_sub<Suspend>(commands, stub, term);
    add_sub<Transfer>(commands, stub, term);
    add_sub<Umount>(commands, stub, term);
    sort_by_name(commands);
}

mp::ReturnCodeVariant cmd::Vm::run(mp::ArgParser* parser)
{
    // `elp help vm` keeps argv as [prog, help, vm]; show the group description.
    if (parser->allArguments().size() >= 2 &&
        parser->allArguments().at(1) == QStringLiteral("help"))
    {
        cout << qUtf8Printable(description()) << "\n";
        return ReturnCode::Ok;
    }

    // Strip the top-level "vm" token and re-parse against Multipass-equivalent
    // subcommands so `elp vm launch -h` shows launch help (not the group help).
    QStringList nested_args = parser->allArguments();
    const auto vm_it = std::find(nested_args.begin() + 1, nested_args.end(), QStringLiteral("vm"));
    if (vm_it == nested_args.end())
    {
        cerr << "Internal error: could not locate vm command token\n";
        return ReturnCode::CommandFail;
    }
    nested_args.erase(vm_it);

    if (!has_non_option_token(nested_args, 1))
    {
        cout << qUtf8Printable(description()) << "\n";
        return ReturnCode::Ok;
    }

    ArgParser nested{nested_args, commands, cout, cerr};
    nested.setVerbosityLevel(parser->verbosityLevel());
    const auto nested_status = nested.parse();

    if (nested_status == ParseCode::HelpRequested)
        return ReturnCode::Ok;

    if (nested_status != ParseCode::Ok || !nested.chosenCommand())
    {
        cerr << "Unknown or missing vm subcommand. Try `" << mp::client_name << " vm -h`.\n";
        return ReturnCode::CommandLineError;
    }

    return nested.chosenCommand()->run(&nested);
}

std::string cmd::Vm::name() const
{
    return "vm";
}

QString cmd::Vm::short_help() const
{
    return QStringLiteral("Create, control and connect to virtual machines");
}

QString cmd::Vm::description() const
{
    QString detail = QStringLiteral(
        "VM management under the `vm` prefix (classic instance lifecycle).\n\n"
        "Available subcommands:\n");
    for (const auto& c : commands)
    {
        detail += QString::fromStdString(fmt::format("  {:<12} {}\n", c->name(), c->short_help()));
    }
    detail += QString::fromStdString(
        fmt::format("\nExample: `{} vm launch`  |  `{} vm list`  |  `{} vm shell`",
                    mp::client_name,
                    mp::client_name,
                    mp::client_name));
    return detail;
}
