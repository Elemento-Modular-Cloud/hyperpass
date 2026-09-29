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

#include "common.h"
#include "temp_dir.h"

#include "provider_store.h"

#include <gmock/gmock.h>
#include <gtest/gtest.h>

namespace mp = multipass;
namespace mpt = multipass::test;

using namespace testing;

TEST(ProviderStore, presetBaseUrls)
{
    EXPECT_EQ(mp::llm_provider_preset_base_url("openai"), "https://api.openai.com/v1");
    EXPECT_EQ(mp::llm_provider_preset_base_url("openrouter"), "https://openrouter.ai/api/v1");
    EXPECT_EQ(mp::llm_provider_preset_base_url("anthropic"), "https://api.anthropic.com/v1");
    EXPECT_TRUE(mp::llm_provider_preset_base_url("custom").empty());
}

TEST(ProviderStore, idMatchingIncludeExclude)
{
    EXPECT_TRUE(mp::llm_provider_id_matches("gpt-4o", {}, {}));
    EXPECT_TRUE(mp::llm_provider_id_matches("gpt-4o", {"gpt-*"}, {}));
    EXPECT_FALSE(mp::llm_provider_id_matches("claude-3", {"gpt-*"}, {}));
    EXPECT_FALSE(mp::llm_provider_id_matches("gpt-4o-free", {"gpt-*"}, {"*-free"}));
    EXPECT_TRUE(mp::llm_provider_id_matches("anthropic/claude-3.5", {"anthropic/*"}, {}));
    EXPECT_FALSE(mp::llm_provider_id_matches("openai/gpt-4o", {"anthropic/*"}, {}));
}

TEST(ProviderStore, createPersistAndReload)
{
    mpt::TempDir dir;
    std::string id;
    {
        mp::ProviderStore store{dir.path()};
        const auto created = store.create("or",
                                          "openrouter",
                                          "",
                                          "sk-or-v1-secretkey",
                                          {"gpt-*"},
                                          {"*-free"});
        id = created.id;
        EXPECT_EQ(created.preset, "openrouter");
        EXPECT_EQ(created.base_url, "https://openrouter.ai/api/v1");
        EXPECT_EQ(created.key_prefix, "sk-or-v1");
        EXPECT_THAT(created.include, ElementsAre("gpt-*"));
        EXPECT_THAT(created.exclude, ElementsAre("*-free"));
        EXPECT_EQ(store.list().size(), 1u);
    }
    mp::ProviderStore reloaded{dir.path()};
    auto got = reloaded.get(id);
    ASSERT_TRUE(got.has_value());
    EXPECT_EQ(got->api_key, "sk-or-v1-secretkey");
    EXPECT_EQ(got->label, "or");
    EXPECT_TRUE(reloaded.touch_refresh(id));
    EXPECT_GT(reloaded.get(id)->last_refresh_at, 0);
    EXPECT_TRUE(reloaded.remove(id));
    EXPECT_FALSE(reloaded.get(id).has_value());
}

TEST(ProviderStore, customRequiresBaseUrl)
{
    mpt::TempDir dir;
    mp::ProviderStore store{dir.path()};
    EXPECT_THROW(store.create("x", "custom", "", "sk-test", {}, {}), std::runtime_error);
    const auto created =
        store.create("x", "custom", "https://example.com/v1/", "sk-test", {}, {});
    EXPECT_EQ(created.base_url, "https://example.com/v1");
}
