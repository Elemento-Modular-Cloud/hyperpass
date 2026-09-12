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

#include <multipass/intent_spec.h>
#include <multipass/json_utils.h>

namespace mp = multipass;

void mp::tag_invoke(const boost::json::value_from_tag&,
                    boost::json::value& json,
                    const mp::IntentSpec& spec)
{
    boost::json::array members;
    for (const auto& member : spec.members)
        members.push_back({
            {"role", member.role},
            {"instance_name", member.instance_name},
        });

    json = {
        {"name", spec.name},
        {"members", members},
        {"creation_timestamp", spec.creation_timestamp},
    };
}

mp::IntentSpec mp::tag_invoke(const boost::json::value_to_tag<mp::IntentSpec>&,
                              const boost::json::value& json)
{
    IntentSpec spec;
    spec.name = value_to<std::string>(json.at("name"));
    spec.creation_timestamp = lookup_or<std::string>(json, "creation_timestamp", {});

    for (const auto& member : json.at("members").as_array())
        spec.members.push_back({value_to<std::string>(member.at("role")),
                                value_to<std::string>(member.at("instance_name"))});

    return spec;
}
