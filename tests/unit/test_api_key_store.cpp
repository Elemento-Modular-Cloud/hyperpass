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
    EXPECT_THAT(created.secret, StartsWith("sk-hp-"));
    EXPECT_FALSE(created.record.sha256_hex.empty());
    EXPECT_EQ(store.list().size(), 1);
    EXPECT_THAT(store.list().front().sha256_hex, Not(HasSubstr(created.secret)));

    EXPECT_TRUE(store.verify(created.secret).has_value());
    EXPECT_FALSE(store.verify("sk-hp-nope").has_value());
    EXPECT_FALSE(store.verify("matcher-token").has_value());
}

TEST(ApiKeyStore, instanceBindingAndRevokeForInstance)
{
    mpt::TempDir dir;
    mp::ApiKeyStore store{dir.path()};
    const auto global = store.create("global");
    const auto scoped = store.create("scoped", "inst-123");
    ASSERT_EQ(store.list().size(), 2);
    EXPECT_TRUE(global.record.instance_id.empty());
    EXPECT_EQ(scoped.record.instance_id, "inst-123");
    EXPECT_TRUE(mp::api_key_allows_instance(global.record, "inst-123"));
    EXPECT_TRUE(mp::api_key_allows_instance(scoped.record, "inst-123"));
    EXPECT_FALSE(mp::api_key_allows_instance(scoped.record, "other"));

    store.revoke_for_instance("inst-123");
    EXPECT_EQ(store.list().size(), 1);
    EXPECT_EQ(store.list().front().id, global.record.id);
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
