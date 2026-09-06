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

#include "api_key_store.h"

#include <gmock/gmock.h>
#include <gtest/gtest.h>

namespace mp = multipass;
namespace mpt = multipass::test;

using namespace testing;

TEST(ApiKeyStore, createShowsSecretOnceAndStoresHashOnly)
{
    mpt::TempDir dir;
    mp::ApiKeyStore store{dir.path()};
    const auto created = store.create("ops");
    EXPECT_THAT(created.secret, StartsWith("sk-elp-"));
    EXPECT_FALSE(created.record.sha256_hex.empty());
    EXPECT_EQ(store.list().size(), 1);
    EXPECT_THAT(store.list().front().sha256_hex, Not(HasSubstr(created.secret)));

    EXPECT_TRUE(store.verify(created.secret).has_value());
    EXPECT_FALSE(store.verify("sk-elp-nope").has_value());
    EXPECT_FALSE(store.verify("matcher-token").has_value());
}

TEST(ApiKeyStore, instanceBindingAndRevokeForInstance)
{
    mpt::TempDir dir;
    mp::ApiKeyStore store{dir.path()};
    const auto global = store.create("global");
    const auto scoped = store.create("scoped", {"inst-123"});
    const auto multi = store.create("multi", {"inst-123", "inst-456"});
    ASSERT_EQ(store.list().size(), 3);
    EXPECT_TRUE(global.record.instance_ids.empty());
    EXPECT_THAT(scoped.record.instance_ids, ElementsAre("inst-123"));
    EXPECT_THAT(multi.record.instance_ids, ElementsAre("inst-123", "inst-456"));
    EXPECT_TRUE(mp::api_key_allows_instance(global.record, "inst-123"));
    EXPECT_TRUE(mp::api_key_allows_instance(scoped.record, "inst-123"));
    EXPECT_FALSE(mp::api_key_allows_instance(scoped.record, "other"));
    EXPECT_TRUE(mp::api_key_allows_instance(multi.record, "inst-456"));
    EXPECT_FALSE(mp::api_key_allows_instance(multi.record, "other"));

    store.revoke_for_instance("inst-123");
    auto remaining = store.list();
    ASSERT_EQ(remaining.size(), 2);
    EXPECT_EQ(remaining[0].id, global.record.id);
    EXPECT_EQ(remaining[1].id, multi.record.id);
    EXPECT_THAT(remaining[1].instance_ids, ElementsAre("inst-456"));
}

TEST(ApiKeyStore, updateScopeAndLabel)
{
    mpt::TempDir dir;
    mp::ApiKeyStore store{dir.path()};
    const auto created = store.create("tmp", {"inst-a"});
    const auto updated =
        store.update(created.record.id, "renamed", {"inst-b", "inst-c"}, true, true);
    ASSERT_TRUE(updated.has_value());
    EXPECT_EQ(updated->label, "renamed");
    EXPECT_THAT(updated->instance_ids, ElementsAre("inst-b", "inst-c"));

    const auto globalized =
        store.update(created.record.id, "", {}, false, true);
    ASSERT_TRUE(globalized.has_value());
    EXPECT_EQ(globalized->label, "renamed");
    EXPECT_TRUE(globalized->instance_ids.empty());
}

TEST(ApiKeyStore, revokeAndReload)
{
    mpt::TempDir dir;
    {
        mp::ApiKeyStore store{dir.path()};
        const auto created = store.create("tmp");
        EXPECT_TRUE(store.revoke_by_id(created.record.id));
        EXPECT_TRUE(store.list().empty());
        store.create("keep");
    }
    mp::ApiKeyStore reloaded{dir.path()};
    EXPECT_EQ(reloaded.list().size(), 1);
    EXPECT_EQ(reloaded.list().front().label, "keep");
}

TEST(ApiKeyStore, migratesLegacyInstanceIdField)
{
    mpt::TempDir dir;
    {
        mp::ApiKeyStore store{dir.path()};
        store.create("legacy", {"inst-legacy"});
    }
    mp::ApiKeyStore reloaded{dir.path()};
    ASSERT_EQ(reloaded.list().size(), 1);
    EXPECT_THAT(reloaded.list().front().instance_ids, ElementsAre("inst-legacy"));
}
