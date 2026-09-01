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

#include <multipass/constants.h>
#include <multipass/resource_pool.h>

namespace mp = multipass;
using namespace testing;

TEST(ResourcePool, claimsAndReleasesMemory)
{
    mp::ResourcePool pool{mp::MemorySize{"8G"}, 4};
    pool.set_memory_reserve(mp::MemorySize{"2G"});

    const auto first = pool.try_claim("a", mp::WorkloadKind::vm, mp::MemorySize{"4G"}, 2);
    EXPECT_TRUE(first.accepted);
    EXPECT_EQ(pool.memory_claimed(), mp::MemorySize{"4G"});
    EXPECT_EQ(pool.memory_available(), mp::MemorySize{"2G"});
    EXPECT_EQ(pool.cpus_claimed(), 2);

    pool.release("a");
    EXPECT_EQ(pool.memory_claimed(), mp::MemorySize{"0B"});
    EXPECT_EQ(pool.cpus_claimed(), 0);
}

TEST(ResourcePool, strictPolicyRejectsOvercommit)
{
    mp::ResourcePool pool{mp::MemorySize{"8G"}, 4};
    pool.set_memory_reserve(mp::MemorySize{"4G"});
    pool.set_memory_policy(mp::MemoryPolicy::strict);

    ASSERT_TRUE(pool.try_claim("vm", mp::WorkloadKind::vm, mp::MemorySize{"4G"}, 1).accepted);
    const auto second = pool.try_claim("llm", mp::WorkloadKind::llm, mp::MemorySize{"1G"}, 1);
    EXPECT_FALSE(second.accepted);
    EXPECT_FALSE(second.message.empty());
    EXPECT_FALSE(pool.has_claim("llm"));
}

TEST(ResourcePool, bestEffortPolicyAcceptsWithWarning)
{
    mp::ResourcePool pool{mp::MemorySize{"8G"}, 4};
    pool.set_memory_reserve(mp::MemorySize{"4G"});
    pool.set_memory_policy(mp::MemoryPolicy::best_effort);

    ASSERT_TRUE(pool.try_claim("vm", mp::WorkloadKind::vm, mp::MemorySize{"4G"}, 1).accepted);
    const auto second = pool.try_claim("llm", mp::WorkloadKind::llm, mp::MemorySize{"2G"}, 1);
    EXPECT_TRUE(second.accepted);
    EXPECT_FALSE(second.message.empty());
    EXPECT_TRUE(pool.has_claim("llm"));
}

TEST(ResourcePool, replacingClaimUsesDelta)
{
    mp::ResourcePool pool{mp::MemorySize{"8G"}, 4};
    pool.set_memory_reserve(mp::MemorySize{"2G"});
    ASSERT_TRUE(pool.try_claim("vm", mp::WorkloadKind::vm, mp::MemorySize{"4G"}, 2).accepted);
    const auto grow = pool.try_claim("vm", mp::WorkloadKind::vm, mp::MemorySize{"6G"}, 2);
    EXPECT_TRUE(grow.accepted);
    EXPECT_EQ(pool.memory_claimed(), mp::MemorySize{"6G"});
}

TEST(ResourcePool, preemptsLlmClaimsFirst)
{
    mp::ResourcePool pool{mp::MemorySize{"8G"}, 4};
    pool.set_memory_reserve(mp::MemorySize{"0B"});
    ASSERT_TRUE(pool.try_claim("vm", mp::WorkloadKind::vm, mp::MemorySize{"4G"}, 1).accepted);
    ASSERT_TRUE(pool.try_claim("m1", mp::WorkloadKind::llm, mp::MemorySize{"3G"}, 1).accepted);

    const auto freed = pool.preempt_llms_to_free(mp::MemorySize{"3G"});
    ASSERT_EQ(freed.size(), 1);
    EXPECT_EQ(freed.front(), "m1");
    EXPECT_FALSE(pool.has_claim("m1"));
    EXPECT_TRUE(pool.has_claim("vm"));
    EXPECT_TRUE(pool.try_claim("vm2", mp::WorkloadKind::vm, mp::MemorySize{"3G"}, 1).accepted);
}

TEST(ResourcePool, forceClaimIgnoresCapacity)
{
    mp::ResourcePool pool{mp::MemorySize{"4G"}, 2};
    pool.set_memory_reserve(mp::MemorySize{"2G"});
    pool.force_claim("leftover", mp::WorkloadKind::vm, mp::MemorySize{"8G"}, 4);
    EXPECT_TRUE(pool.has_claim("leftover"));
    EXPECT_EQ(pool.memory_claimed(), mp::MemorySize{"8G"});
}

TEST(ResourcePool, checkAdmitDoesNotMutateClaims)
{
    mp::ResourcePool pool{mp::MemorySize{"8G"}, 4};
    pool.set_memory_reserve(mp::MemorySize{"4G"});
    pool.set_memory_policy(mp::MemoryPolicy::strict);
    ASSERT_TRUE(pool.try_claim("vm", mp::WorkloadKind::vm, mp::MemorySize{"4G"}, 1).accepted);

    const auto denied = pool.check_admit(mp::MemorySize{"1G"}, 1);
    EXPECT_FALSE(denied.accepted);
    EXPECT_EQ(pool.memory_claimed(), mp::MemorySize{"4G"});

    pool.set_memory_policy(mp::MemoryPolicy::best_effort);
    const auto warned = pool.check_admit(mp::MemorySize{"1G"}, 1);
    EXPECT_TRUE(warned.accepted);
    EXPECT_FALSE(warned.message.empty());
    EXPECT_EQ(pool.memory_claimed(), mp::MemorySize{"4G"});
}
