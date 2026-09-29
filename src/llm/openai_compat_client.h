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

#include <string>
#include <vector>

namespace multipass
{

struct OpenAiCompatModel
{
    std::string id;
    std::string owned_by;
};

// GET {base_url}/models with Authorization: Bearer {api_key}.
// base_url should already include the /v1 suffix (no trailing slash).
std::vector<OpenAiCompatModel> openai_compat_list_models(const std::string& base_url,
                                                         const std::string& api_key);

} // namespace multipass
