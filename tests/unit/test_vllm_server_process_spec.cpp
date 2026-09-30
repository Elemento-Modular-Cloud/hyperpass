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

#include "vllm_server_process_spec.h"

namespace mp = multipass;
using namespace testing;

namespace
{
mp::VllmServerOptions base_options()
{
    mp::VllmServerOptions options;
    options.program = "vllm";
    options.launch_mode = "cli";
    options.model = "meta-llama/Llama-3.1-8B";
    options.port = 18080;
    options.openai_id = "llama-3.1-8b";
    options.dtype = "bfloat16";
    options.gpu_memory_utilization = 0.85;
    options.max_model_len = 4096;
    return options;
}
} // namespace

TEST(TestVllmServerProcessSpec, cliServeBindsLoopback)
{
    const mp::VllmServerProcessSpec spec{base_options()};
    EXPECT_EQ(spec.program(), "vllm");
    EXPECT_EQ(spec.identifier(), "vllm-18080");
    EXPECT_EQ(spec.arguments(),
              QStringList({"serve",
                           "meta-llama/Llama-3.1-8B",
                           "--host",
                           "127.0.0.1",
                           "--port",
                           "18080",
                           "--served-model-name",
                           "llama-3.1-8b",
                           "--dtype",
                           "bfloat16",
                           "--gpu-memory-utilization",
                           "0.85",
                           "--max-model-len",
                           "4096"}));
}

TEST(TestVllmServerProcessSpec, pythonModuleLaunchMode)
{
    auto options = base_options();
    options.program = "python3";
    options.launch_mode = "python";
    options.dtype.clear();
    options.gpu_memory_utilization = 0;
    options.max_model_len = 0;
    options.openai_id.clear();

    const mp::VllmServerProcessSpec spec{options};
    EXPECT_EQ(spec.arguments(),
              QStringList({"-m",
                           "vllm.entrypoints.openai.api_server",
                           "--host",
                           "127.0.0.1",
                           "--port",
                           "18080",
                           "--model",
                           "meta-llama/Llama-3.1-8B"}));
}

TEST(TestVllmServerProcessSpec, environmentSetsHfCacheAndToken)
{
    auto options = base_options();
    options.hf_cache_dir = "/tmp/elp-hf-cache";
    options.hf_token = "hf_test_token";
    const mp::VllmServerProcessSpec spec{options};
    const auto env = spec.environment();
    EXPECT_EQ(env.value("HF_HUB_CACHE"), "/tmp/elp-hf-cache");
    EXPECT_EQ(env.value("HF_TOKEN"), "hf_test_token");
}
