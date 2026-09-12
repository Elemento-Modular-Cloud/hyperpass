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

#include "llm_load_params.h"

namespace mp = multipass;
using namespace testing;

TEST(TestLlmLoadParams, detectsMoeModelNames)
{
    EXPECT_TRUE(mp::looks_like_moe_model("Mixtral-8x7B-Instruct"));
    EXPECT_TRUE(mp::looks_like_moe_model("Qwen3-30B-A3B"));
    EXPECT_TRUE(mp::looks_like_moe_model("gpt-oss-20b"));
    EXPECT_TRUE(mp::looks_like_moe_model("DeepSeek-V3"));
    EXPECT_TRUE(mp::looks_like_moe_model("some-moe-chat"));
    EXPECT_FALSE(mp::looks_like_moe_model("Llama-3.1-8B-Instruct"));
    EXPECT_FALSE(mp::looks_like_moe_model("DeepSeek-R1-Distill-Qwen-7B"));
    EXPECT_FALSE(mp::looks_like_moe_model(""));
}

TEST(TestLlmLoadParams, kvScaleMatchesQuant)
{
    EXPECT_DOUBLE_EQ(mp::kv_cache_byte_scale("f16", "f16"), 1.0);
    EXPECT_DOUBLE_EQ(mp::kv_cache_byte_scale("q8_0", "q8_0"), 0.5);
    EXPECT_DOUBLE_EQ(mp::kv_cache_byte_scale("q4_0", "q4_0"), 0.25);
}

TEST(TestLlmLoadParams, appliesSmartDefaultsOnGpu)
{
    mp::LoadModelRequest request;
    request.set_model_id("Llama-3.1-8B");
    const auto resolved = mp::resolve_llm_load(request, true);
    EXPECT_EQ(resolved.ctx_size, 4096);
    EXPECT_EQ(resolved.max_tokens, 0);
    EXPECT_EQ(resolved.llama.n_gpu_layers, "auto");
    EXPECT_EQ(resolved.llama.flash_attn, "auto");
    EXPECT_EQ(resolved.llama.cache_type_k, "q8_0");
    EXPECT_EQ(resolved.llama.cache_type_v, "q8_0");
    EXPECT_EQ(resolved.llama.cache_reuse, 256);
    EXPECT_TRUE(resolved.llama.fit);
    EXPECT_EQ(resolved.llama.parallel, 1);
    EXPECT_FALSE(resolved.llama.cpu_moe);
}

TEST(TestLlmLoadParams, cpuBackendDefaultsToZeroGpuLayers)
{
    mp::LoadModelRequest request;
    request.set_model_id("Llama-3.1-8B");
    const auto resolved = mp::resolve_llm_load(request, false);
    EXPECT_EQ(resolved.llama.n_gpu_layers, "0");
}

TEST(TestLlmLoadParams, paramsOverrideLegacyCtxAndEnableMoe)
{
    mp::LoadModelRequest request;
    request.set_model_id("Mixtral-8x7B");
    request.set_ctx_size(2048);
    request.set_max_tokens(128);
    auto* params = request.mutable_params();
    params->set_ctx_size(16384);
    params->set_max_tokens(512);
    params->set_n_gpu_layers("all");
    params->set_flash_attn("on");
    params->set_cache_type_k("q4_0");
    params->set_moe_offload("cpu");
    params->set_cache_reuse(128);
    params->set_fit(false);
    params->set_parallel(2);

    const auto resolved = mp::resolve_llm_load(request, true);
    EXPECT_EQ(resolved.ctx_size, 16384);
    EXPECT_EQ(resolved.max_tokens, 512);
    EXPECT_EQ(resolved.llama.n_gpu_layers, "all");
    EXPECT_EQ(resolved.llama.flash_attn, "on");
    EXPECT_EQ(resolved.llama.cache_type_k, "q4_0");
    EXPECT_EQ(resolved.llama.cache_type_v, "q4_0");
    EXPECT_EQ(resolved.llama.cache_reuse, 128);
    EXPECT_FALSE(resolved.llama.fit);
    EXPECT_EQ(resolved.llama.parallel, 2);
    EXPECT_TRUE(resolved.llama.cpu_moe);
}

TEST(TestLlmLoadParams, autoMoeFromModelId)
{
    mp::LoadModelRequest request;
    request.set_model_id("Qwen3-30B-A3B-Instruct");
    const auto resolved = mp::resolve_llm_load(request, true);
    EXPECT_TRUE(resolved.llama.cpu_moe);
    EXPECT_EQ(resolved.echoed.moe_offload(), "auto");
}

TEST(TestLlmLoadParams, jsonRoundTripPreservesOptionalFields)
{
    mp::LlmLoadParams params;
    params.set_ctx_size(8192);
    params.set_n_gpu_layers("auto");
    params.set_fit(true);
    const auto back = mp::llm_load_params_from_json(mp::llm_load_params_to_json(params));
    EXPECT_EQ(back.ctx_size(), 8192);
    EXPECT_EQ(back.n_gpu_layers(), "auto");
    EXPECT_TRUE(back.fit());
}
