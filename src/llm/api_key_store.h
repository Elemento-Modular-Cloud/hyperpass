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

#include <algorithm>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace multipass
{

struct ApiKeyRecord
{
    std::string id;
    std::string prefix;
    std::string label;
    std::string sha256_hex;
    long long created_at{0};
    // Empty = global (all instances). Non-empty = allow only these instance ids.
    std::vector<std::string> instance_ids;
};

inline bool api_key_allows_instance(const ApiKeyRecord& key, const std::string& instance_id)
{
    if (key.instance_ids.empty())
        return true;
    return std::find(key.instance_ids.begin(), key.instance_ids.end(), instance_id) !=
           key.instance_ids.end();
}

class ApiKeyStore
{
public:
    explicit ApiKeyStore(Path data_directory);

    struct CreatedKey
    {
        ApiKeyRecord record;
        std::string secret;
    };

    CreatedKey create(const std::string& label,
                      const std::vector<std::string>& instance_ids = {});
    std::optional<ApiKeyRecord> update(const std::string& id,
                                       const std::string& label,
                                       const std::vector<std::string>& instance_ids,
                                       bool update_label,
                                       bool update_instance_ids);
    std::vector<ApiKeyRecord> list() const;
    bool revoke_by_id(const std::string& id);
    bool revoke_by_prefix(const std::string& prefix);
    void revoke_for_instance(const std::string& instance_id);
    std::optional<ApiKeyRecord> verify(const std::string& secret) const;

private:
    void load();
    void save() const;

    Path store_path;
    mutable std::mutex mutex;
    std::vector<ApiKeyRecord> keys;
};

} // namespace multipass
