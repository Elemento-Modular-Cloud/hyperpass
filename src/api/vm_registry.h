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

#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace multipass::api
{

struct RegisteredVm
{
    std::string vm_uid;
    std::string vm_name;
    std::string username;
    std::string region{"local"};
    std::string template_id;
    std::string service_id;
    std::string spec_json; // public Spot spec (no auth secrets / cloud_init_b64)
    std::string source{"elp"}; // "elp" | "multipass"
};

/** Empty or unknown → "elp". */
std::string normalize_vm_source(std::string_view source);

/**
 * Persistent sidecar registry mapping Spot vm_uid ↔ Electros LaunchPad instance name.
 * Stored as JSON under the user data directory. v1 matcher records are ignored.
 */
class VmRegistry
{
public:
    explicit VmRegistry(std::string path);

    static std::string default_path();

    RegisteredVm upsert(RegisteredVm record);
    bool remove(const std::string& vm_uid);
    std::optional<RegisteredVm> find_by_uid(const std::string& vm_uid) const;
    std::optional<RegisteredVm> find_by_name(const std::string& vm_name,
                                             std::string_view source) const;
    std::vector<RegisteredVm> all() const;

private:
    void load_unlocked();
    void save_unlocked() const;

    std::string path;
    mutable std::mutex mutex;
    std::unordered_map<std::string, RegisteredVm> by_uid;
};

} // namespace multipass::api
