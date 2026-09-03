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

#include <QString>
#include <QStringList>

#include <optional>
#include <vector>

namespace multipass::utils
{

struct ProcessMatch
{
    qint64 pid{0};
    QString command_line;
};

std::vector<ProcessMatch> parse_ps_table(const QByteArray& output);
std::vector<ProcessMatch> list_processes();
std::optional<qint64> find_pid_containing(const QString& program_needle, const QString& arg_needle);
QString cli_flag_value(const QString& command_line, const QStringList& flags);
bool pid_is_alive(qint64 pid);
void terminate_pid(qint64 pid);

} // namespace multipass::utils
