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

#include <multipass/cli/command.h>

namespace multipass::cmd
{
class PortForward final : public Command
{
public:
    using Command::Command;
    ReturnCodeVariant run(ArgParser* parser) override;

    std::string name() const override;
    std::vector<std::string> aliases() const override;
    QString short_help() const override;
    QString description() const override;

private:
    ReturnCodeVariant run_add(ArgParser* parser);
    ReturnCodeVariant run_list(ArgParser* parser);
    ReturnCodeVariant run_remove(ArgParser* parser);
};
} // namespace multipass::cmd
