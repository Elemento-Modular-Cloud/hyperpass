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

#include "vllm_memory_budget.h"

namespace mp = multipass;
using namespace testing;

namespace
{
constexpr long long gib = 1024LL * 1024 * 1024;
} // namespace

TEST(TestVllmMemoryBudget, smallModelYieldsLowUtil)
{
    // ~16 GiB weights on 120 GiB GPU with 8k ctx → above floor, below host cap.
    const auto util =
        mp::estimate_vllm_gpu_memory_utilization(16 * gib, 8192, 120 * gib, 0.80);
    EXPECT_GT(util, mp::vllm_util_floor);
    EXPECT_LT(util, 0.30);
}

TEST(TestVllmMemoryBudget, largeModelClampedToHostCap)
{
    const auto util =
        mp::estimate_vllm_gpu_memory_utilization(100 * gib, 8192, 120 * gib, 0.80);
    EXPECT_DOUBLE_EQ(util, 0.80);
}

TEST(TestVllmMemoryBudget, unknownGpuTotalFallsBackToHostCap)
{
    const auto util = mp::estimate_vllm_gpu_memory_utilization(4 * gib, 8192, 0, 0.80);
    EXPECT_DOUBLE_EQ(util, 0.80);
}

TEST(TestVllmMemoryBudget, tinyBudgetHitsFloor)
{
    const auto util =
        mp::estimate_vllm_gpu_memory_utilization(0, 2048, 120 * gib, 0.80);
    EXPECT_DOUBLE_EQ(util, mp::vllm_util_floor);
}

TEST(TestVllmMemoryBudget, budgetBytesIncludesWeightsKvAndOverhead)
{
    const auto kv = mp::vllm_kv_budget_bytes(4096);
    const auto budget = mp::vllm_budget_bytes(2 * gib, 4096);
    EXPECT_EQ(budget, 2 * gib + kv + mp::vllm_runtime_overhead_bytes);
}

TEST(TestVllmMemoryBudget, hostCapIsSane)
{
    const auto cap = mp::vllm_host_util_cap();
    EXPECT_TRUE(cap == 0.80 || cap == 0.90);
}

TEST(TestVllmMemoryBudget, probeGpuTotalBytesPositiveOnThisHost)
{
    // GB10 reports N/A via nvidia-smi; helper should fall back to host RAM.
    const auto total = mp::probe_gpu_total_bytes();
    EXPECT_GT(total, 0);
}

TEST(TestVllmMemoryBudget, claimBytesUsesUtilTimesGpuTotal)
{
    const auto claim = mp::vllm_claim_bytes(0.10, 120 * gib, 5 * gib, 8192);
    EXPECT_EQ(claim, static_cast<long long>(0.10 * 120 * gib));
}

TEST(TestVllmMemoryBudget, claimBytesFallsBackToBudgetWhenTotalUnknown)
{
    const auto budget = mp::vllm_budget_bytes(5 * gib, 8192);
    const auto claim = mp::vllm_claim_bytes(0.10, 0, 5 * gib, 8192);
    EXPECT_EQ(claim, budget);
}
