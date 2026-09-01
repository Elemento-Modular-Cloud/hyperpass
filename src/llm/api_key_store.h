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
};

class ApiKeyStore
{
public:
    explicit ApiKeyStore(Path data_directory);

    struct CreatedKey
    {
        ApiKeyRecord record;
        std::string secret;
    };

    CreatedKey create(const std::string& label);
    std::vector<ApiKeyRecord> list() const;
    bool revoke_by_id(const std::string& id);
    bool revoke_by_prefix(const std::string& prefix);
    std::optional<ApiKeyRecord> verify(const std::string& secret) const;

private:
    void load();
    void save() const;

    Path store_path;
    std::vector<ApiKeyRecord> keys;
};

} // namespace multipass
