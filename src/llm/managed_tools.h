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

#include <multipass/path.h>

#include <QString>
#include <QStringList>

namespace multipass::llm
{

// Pinned managed-tool releases. Bump deliberately when upgrading.
constexpr auto pinned_llmfit_version = "v1.1.14";
constexpr auto pinned_llama_build = "b10819";

constexpr auto tool_llmfit = "llmfit";
constexpr auto tool_llama_server = "llama-server";

QString managed_tools_root(const Path& data_directory);
QString managed_version_dir(const QString& tools_root, const QString& tool_name);
QString find_in_managed(const QString& tools_root, const QString& tool_name, const QStringList& names);
bool is_under_managed_tools(const QString& binary_path, const QString& tools_root);

} // namespace multipass::llm
