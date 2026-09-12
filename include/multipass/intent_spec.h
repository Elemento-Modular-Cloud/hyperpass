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

#include <boost/json.hpp>

#include <string>
#include <vector>

namespace multipass
{

// A named group of instances launched together (e.g. "test-app-1" made of a
// redis and a postgres instance). Membership is also mirrored into each
// member instance's own VMSpecs.metadata ("intent"/"intent_role"); this
// registry is the source of truth for the group itself (name, ordered
// members, creation time), independent of any single member.
struct IntentSpec
{
    struct Member
    {
        std::string role;          // e.g. "redis", or a user-chosen label for inline members
        std::string instance_name; // the launched VM instance's name, or an LLM session's instance_id
        std::string kind{"vm"};    // "vm" or "llm"; defaults to "vm" for older persisted records

        friend inline bool operator==(const Member&, const Member&) = default;
    };

    std::string name;
    std::vector<Member> members;
    std::string creation_timestamp; // ISO-8601

    friend inline bool operator==(const IntentSpec&, const IntentSpec&) = default;
};

void tag_invoke(const boost::json::value_from_tag&,
               boost::json::value& json,
               const IntentSpec& spec);
IntentSpec tag_invoke(const boost::json::value_to_tag<IntentSpec>&, const boost::json::value& json);

} // namespace multipass
