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
// CUDA builds ship later than the CPU pin; b10819 has no ubuntu-cuda assets.
constexpr auto pinned_llama_cuda_build = "b11062";

constexpr auto tool_llmfit = "llmfit";
constexpr auto tool_llama_server = "llama-server";
constexpr auto tool_llama_server_cuda = "llama-server-cuda";
constexpr auto tool_mlx = "mlx";
constexpr auto tool_vllm = "vllm";

/// Installable backend id for the CUDA llama.cpp archive (Models → Setup).
constexpr auto backend_llamacpp_cuda = "llamacpp-cuda";

QString managed_tools_root(const Path& data_directory);
QString managed_version_dir(const QString& tools_root, const QString& tool_name);
QString find_in_managed(const QString& tools_root, const QString& tool_name, const QStringList& names);
bool is_under_managed_tools(const QString& binary_path, const QString& tools_root);

/// Managed pip venvs live under `<tools_root>/venvs/<backend_id>/`.
QString managed_venv_dir(const QString& tools_root, const QString& backend_id);
QString managed_venv_python(const QString& tools_root, const QString& backend_id);
QString pip_package_for_backend(const QString& backend_id);
bool is_pip_backend(const QString& backend_id);

} // namespace multipass::llm
