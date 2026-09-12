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

#include <optional>
#include <string>

namespace multipass
{

struct IntentServiceTemplate
{
    std::string image;
    std::string cloud_init_user_data;
};

// Named service templates for `elp intent create --service <role>` members
// that don't specify their own image/cloud-init. See
// data/cloud-init-yaml/cloud-init-<role>.yaml for the reference copy of each
// template's cloud-init content (kept in sync manually).
std::optional<IntentServiceTemplate> find_intent_service_template(const std::string& role);

} // namespace multipass
