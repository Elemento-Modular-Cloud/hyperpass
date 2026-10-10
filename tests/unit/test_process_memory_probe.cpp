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

#include "process_memory_probe.h"

#include <unistd.h>

namespace mp = multipass;
using namespace testing;

TEST(TestProcessMemoryProbe, parsesNvidiaSmiComputeAppsCsv)
{
    const auto csv = "1234, 1024\n"
                     "5678, 2048\n"
                     "1234, 512\n" // accumulate same pid
                     "9999, [N/A]\n";
    const auto map = mp::parse_nvidia_smi_compute_apps_csv(csv);
    ASSERT_EQ(map.size(), 2u);
    EXPECT_EQ(map.at(1234), (1024LL + 512LL) * 1024 * 1024);
    EXPECT_EQ(map.at(5678), 2048LL * 1024 * 1024);
}

TEST(TestProcessMemoryProbe, sumsGpuMemoryForTree)
{
    std::unordered_map<std::int64_t, long long> gpu{
        {100, 10LL * 1024 * 1024},
        {101, 20LL * 1024 * 1024},
        {200, 99LL * 1024 * 1024},
    };
    const std::unordered_set<std::int64_t> tree{100, 101};
    EXPECT_EQ(mp::sum_gpu_memory_for_tree(100, gpu, tree), 30LL * 1024 * 1024);
}

TEST(TestProcessMemoryProbe, collectTreeIncludesSelf)
{
    const auto tree = mp::collect_process_tree_pids(static_cast<std::int64_t>(getpid()));
    EXPECT_TRUE(tree.contains(static_cast<std::int64_t>(getpid())));
}
