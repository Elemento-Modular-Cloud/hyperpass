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

#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace multipass
{

inline constexpr auto openai_compat_backend = "openai-compat";

struct LlmProviderRecord
{
    std::string id;
    std::string label;
    std::string preset; // openai | openrouter | anthropic | custom
    std::string base_url;
    std::string api_key;
    std::string key_prefix; // first chars for display; never empty when key set
    std::vector<std::string> include;
    std::vector<std::string> exclude;
    long long created_at{0};
    long long last_refresh_at{0};
};

std::string llm_provider_preset_base_url(const std::string& preset);
std::string llm_provider_key_prefix(const std::string& api_key);
bool llm_provider_id_matches(const std::string& model_id,
                             const std::vector<std::string>& include,
                             const std::vector<std::string>& exclude);

class ProviderStore
{
public:
    explicit ProviderStore(Path data_directory);

    LlmProviderRecord create(const std::string& label,
                             const std::string& preset,
                             const std::string& base_url,
                             const std::string& api_key,
                             const std::vector<std::string>& include,
                             const std::vector<std::string>& exclude);
    std::optional<LlmProviderRecord> update(const std::string& id,
                                            const std::string& label,
                                            bool update_label,
                                            const std::string& base_url,
                                            bool update_base_url,
                                            const std::string& api_key,
                                            bool update_api_key,
                                            const std::vector<std::string>& include,
                                            bool update_include,
                                            const std::vector<std::string>& exclude,
                                            bool update_exclude);
    std::vector<LlmProviderRecord> list() const;
    std::optional<LlmProviderRecord> get(const std::string& id) const;
    bool remove(const std::string& id);
    bool touch_refresh(const std::string& id);

private:
    void load();
    void save() const;

    Path store_path;
    mutable std::mutex mutex;
    std::vector<LlmProviderRecord> providers;
};

} // namespace multipass
