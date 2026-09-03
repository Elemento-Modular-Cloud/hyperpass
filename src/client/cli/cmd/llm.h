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

#include <QString>

namespace multipass::cmd
{
class Llm final : public Command
{
public:
    using Command::Command;
    ReturnCodeVariant run(ArgParser* parser) override;

    std::string name() const override;
    QString short_help() const override;
    QString description() const override;

private:
    ParseCode parse_args(ArgParser* parser);

    QString subcommand;
    QString model_id;
    QString quant;
    QString use_case;
    QString query;
    QString key_label;
    QString key_id;
    QString key_instance;
    int limit{10};
    int ctx_size{4096};
    int max_tokens{0};
    bool recommend_only{false};
};
} // namespace multipass::cmd
