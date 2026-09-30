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

#include "mlx_repo.h"

namespace llm = multipass::llm;
using namespace testing;

TEST(TestMlxRepo, looksLikeMlxRepoRecognizesCommunityAndMlxSuffix)
{
    EXPECT_TRUE(llm::looks_like_mlx_repo(std::string{"mlx-community/Qwen2.5-7B-4bit"}));
    EXPECT_TRUE(llm::looks_like_mlx_repo(std::string{"org/DeepSeek-R1-Distill-Qwen-7B-MLX-8bit"}));
    EXPECT_TRUE(llm::looks_like_mlx_repo(std::string{"org/model-MLX"}));
    EXPECT_FALSE(llm::looks_like_mlx_repo(std::string{"deepseek-ai/DeepSeek-R1-Distill-Qwen-7B"}));
    EXPECT_FALSE(llm::looks_like_mlx_repo(std::string{"bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF"}));
}

TEST(TestMlxRepo, resolveMapsBaseCheckpointToCommunityQuant)
{
    // Chat-tuned names keep their base; plain bases prefer an -it candidate.
    EXPECT_EQ(llm::resolve_mlx_repo("deepseek-ai/DeepSeek-R1-Distill-Qwen-7B", "mlx-8bit"),
              "mlx-community/DeepSeek-R1-Distill-Qwen-7B-8bit");
    EXPECT_EQ(llm::resolve_mlx_repo("deepseek-ai/DeepSeek-R1-Distill-Qwen-7B", "mlx-4bit"),
              "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit");
    EXPECT_EQ(llm::resolve_mlx_repo("Qwen2.5-Coder-7B-Instruct", ""),
              "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit");
    EXPECT_EQ(llm::resolve_mlx_repo("Gemma-2-2B", "mlx-4bit"),
              "mlx-community/Gemma-2-2B-it-4bit");
}

TEST(TestMlxRepo, candidatesPreferInstructThenBase)
{
    const auto c = llm::mlx_repo_candidates("Gemma-2-2B", "mlx-4bit");
    ASSERT_GE(c.size(), 2u);
    EXPECT_EQ(c.front(), "mlx-community/Gemma-2-2B-it-4bit");
    EXPECT_NE(std::find(c.begin(), c.end(), "mlx-community/Gemma-2-2B-4bit"), c.end());
    EXPECT_NE(std::find(c.begin(), c.end(), "mlx-community/gemma-2-2b-it-4bit"), c.end());
}

TEST(TestMlxRepo, resolvePrefersExplicitMlxRepo)
{
    EXPECT_EQ(llm::resolve_mlx_repo("deepseek-ai/DeepSeek-R1-Distill-Qwen-7B",
                                    "mlx-8bit",
                                    "mlx-community/DeepSeek-R1-Distill-Qwen-7B-8bit"),
              "mlx-community/DeepSeek-R1-Distill-Qwen-7B-8bit");
    EXPECT_EQ(llm::resolve_mlx_repo("mlx-community/Qwen2.5-7B-4bit", "mlx-8bit"),
              "mlx-community/Qwen2.5-7B-4bit");
}

TEST(TestMlxRepo, resolveIgnoresNonMlxHfRepoHint)
{
    // Catalogue sometimes places the base checkpoint in hf_repo; never pass that
    // through to mlx_lm.server.
    EXPECT_EQ(llm::resolve_mlx_repo("deepseek-ai/DeepSeek-R1-Distill-Qwen-7B",
                                    "mlx-8bit",
                                    "deepseek-ai/DeepSeek-R1-Distill-Qwen-7B"),
              "mlx-community/DeepSeek-R1-Distill-Qwen-7B-8bit");
}
