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

#include <string>
#include <vector>

namespace multipass::llm
{

struct BackendProbeResult
{
    std::string id;
    std::string name;
    std::string status;
    std::string detail;
    std::string binary_path;
    std::string install_hint;
    bool required{false};
    bool active{false};
    bool installable{false};
};

std::vector<BackendProbeResult> probe_backends(const std::string& selected_inference_id,
                                               const QString& managed_tools_dir = {});

} // namespace multipass::llm
