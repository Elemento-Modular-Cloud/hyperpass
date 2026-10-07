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

namespace multipass::llm
{

// Search order: env override → managed tools dir → PATH.
QString locate_binary(const char* env_var,
                      const QStringList& names,
                      const QString& managed_tools_dir = {},
                      const QString& managed_tool_name = {});

/// Prefer managed CUDA llama-server when NVIDIA is present, else CPU managed / PATH.
QString locate_llama_server(const QString& managed_tools_dir = {});

} // namespace multipass::llm
