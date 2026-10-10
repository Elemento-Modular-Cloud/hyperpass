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

#include "llm_memory_claim.h"

namespace mp = multipass;
using namespace testing;

namespace
{
constexpr long long gib = 1024LL * 1024 * 1024;
} // namespace

TEST(TestLlmMemoryClaim, llamaParallelDoesNotMultiplyCtxBudget)
{
    // --ctx-size is the total KV pool; --parallel only slices it into slots.
    const auto one = mp::estimate_llama_claim_bytes(2 * gib, 8192, 1, "q8_0", "q8_0", {});
    const auto four = mp::estimate_llama_claim_bytes(2 * gib, 8192, 4, "q8_0", "q8_0", {});
    EXPECT_EQ(four, one);
}

TEST(TestLlmMemoryClaim, mlxIsWeightsPlusOverhead)
{
    const auto claim = mp::estimate_mlx_claim_bytes(4 * gib);
    EXPECT_EQ(claim, 4 * gib + 768LL * 1024 * 1024);
}

TEST(TestLlmMemoryClaim, llamaQ4KvSmallerThanF16)
{
    const auto q4 = mp::estimate_llama_claim_bytes(gib, 8192, 1, "q4_0", "q4_0", {});
    const auto f16 = mp::estimate_llama_claim_bytes(gib, 8192, 1, "f16", "f16", {});
    EXPECT_LT(q4, f16);
}
