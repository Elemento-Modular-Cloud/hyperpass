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

#include "runners/model_format.h"
#include "runners/runner_registry.h"

#include <multipass/constants.h>

namespace llm = multipass::llm;
using namespace testing;

TEST(TestRunnerRegistry, formatForRunnerMapsIds)
{
    EXPECT_EQ(llm::format_for_runner(llm::runner_llamacpp), llm::format_gguf);
    EXPECT_EQ(llm::format_for_runner(llm::runner_mlx), llm::format_mlx);
    EXPECT_EQ(llm::format_for_runner(llm::runner_vllm), llm::format_hf);
    EXPECT_EQ(llm::format_for_runner("unknown"), llm::format_gguf);
}

TEST(TestRunnerRegistry, listsLlamaMlxAndVllm)
{
    llm::RunnerRegistry registry;
    std::vector<std::string> ids;
    for (const auto* runner : registry.all())
        ids.push_back(runner->id());

    EXPECT_THAT(ids, Contains(llm::runner_llamacpp));
    EXPECT_THAT(ids, Contains(llm::runner_mlx));
    EXPECT_THAT(ids, Contains(llm::runner_vllm));
}

TEST(TestRunnerRegistry, resolveHonorsExplicitRuntimes)
{
    llm::RunnerRegistry registry;

    const auto llama = registry.resolve("llamacpp");
    ASSERT_NE(llama.runner, nullptr);
    EXPECT_EQ(llama.runner->id(), llm::runner_llamacpp);

    const auto vllm = registry.resolve("vllm");
    ASSERT_NE(vllm.runner, nullptr);
    EXPECT_EQ(vllm.runner->id(), llm::runner_vllm);

    if constexpr (multipass::enable_mlx_backend)
    {
#ifdef Q_OS_MACOS
        const auto mlx = registry.resolve("mlx");
        ASSERT_NE(mlx.runner, nullptr);
        EXPECT_EQ(mlx.runner->id(), llm::runner_mlx);
#endif
    }
}

TEST(TestRunnerRegistry, autoDoesNotSelectVllm)
{
    llm::RunnerRegistry registry;
    const auto selected = registry.select_default();
    ASSERT_NE(selected.runner, nullptr);
    EXPECT_EQ(selected.runner->id(), llm::runner_llamacpp);
}

TEST(TestRunnerRegistry, llamaSessionNamesEncodeDevice)
{
    llm::RunnerRegistry registry;
    const auto* llama = registry.get(llm::runner_llamacpp);
    ASSERT_NE(llama, nullptr);
    EXPECT_EQ(llama->session_backend_name(llm::RunnerDevice::cpu), "llamacpp");
    EXPECT_EQ(llama->session_backend_name(llm::RunnerDevice::metal), "llamacpp-metal");
    EXPECT_EQ(llama->session_backend_name(llm::RunnerDevice::cuda), "llamacpp-cuda");
}
