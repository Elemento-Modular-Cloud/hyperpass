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

#pragma once

#include <multipass/cli/alias_dict.h>
#include <multipass/cli/command.h>

#include <memory>
#include <vector>

namespace multipass::cmd
{
/// Top-level group for Multipass-equivalent VM commands (`elp vm <cmd>`).
class Vm final : public Command
{
public:
    Vm(Rpc::StubInterface& stub, Terminal* term, AliasDict& aliases);

    ReturnCodeVariant run(ArgParser* parser) override;

    std::string name() const override;
    QString short_help() const override;
    QString description() const override;

    const std::vector<Command::UPtr>& subcommands() const
    {
        return commands;
    }

private:
    std::vector<Command::UPtr> commands;
};
} // namespace multipass::cmd
