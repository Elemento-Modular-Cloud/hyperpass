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

#include "llama_server_process_spec.h"

#include <multipass/logging/level.h>

namespace mp = multipass;
using namespace testing;

namespace
{
mp::LlamaServerOptions base_options(int max_tokens = 0, QString library_dir = {})
{
    mp::LlamaServerOptions options;
    options.program = "/opt/llama-server";
    options.model_path = "/models/nemotron.gguf";
    options.openai_id = "nemotron-abc";
    options.port = 52792;
    options.ctx_size = 8192;
    options.n_gpu_layers = "99";
    options.max_tokens = max_tokens;
    options.library_dir = std::move(library_dir);
    return options;
}

mp::LlamaServerProcessSpec make_spec(int max_tokens = 0, QString library_dir = {})
{
    return mp::LlamaServerProcessSpec{base_options(max_tokens, std::move(library_dir))};
}
} // namespace

TEST(TestLlamaServerProcessSpec, programAndIdentifier)
{
    const auto spec = make_spec();
    EXPECT_EQ(spec.program(), "/opt/llama-server");
    EXPECT_EQ(spec.identifier(), "nemotron-abc");
    EXPECT_TRUE(spec.apparmor_profile().isEmpty());
}

TEST(TestLlamaServerProcessSpec, argumentsBindLoopbackWithSingleSlot)
{
    const auto spec = make_spec();
    const auto args = spec.arguments();

    EXPECT_EQ(args, QStringList({"-m",
                                 "/models/nemotron.gguf",
                                 "--host",
                                 "127.0.0.1",
                                 "--port",
                                 "52792",
                                 "--ctx-size",
                                 "8192",
                                 "--alias",
                                 "nemotron-abc",
                                 "--n-gpu-layers",
                                 "99",
                                 "--parallel",
                                 "1"}));
}

TEST(TestLlamaServerProcessSpec, argumentsIncludeMmprojWhenProvided)
{
    auto options = base_options();
    options.model_path = "/models/gemma.gguf";
    options.openai_id = "gemma-abc";
    options.mmproj_path = "/models/gemma-mmproj.gguf";
    const auto spec = mp::LlamaServerProcessSpec{options};
    const auto args = spec.arguments();
    EXPECT_TRUE(args.contains("--mmproj"));
    EXPECT_EQ(args.at(args.indexOf("--mmproj") + 1), "/models/gemma-mmproj.gguf");
}

TEST(TestLlamaServerProcessSpec, stderrIsDebugBecauseLlamaLogsInfoThere)
{
    EXPECT_EQ(make_spec().error_log_level(), mp::logging::Level::debug);
}

TEST(TestLlamaServerProcessSpec, disablesWebUiAndRestrictsCorsViaEnv)
{
    const auto env = make_spec().environment();
    EXPECT_EQ(env.value("LLAMA_ARG_CORS_ORIGINS"), "localhost");
    EXPECT_EQ(env.value("LLAMA_ARG_WEBUI"), "0");
    EXPECT_EQ(env.value("LLAMA_ARG_UI"), "0");
}

TEST(TestLlamaServerProcessSpec, prependsLibraryDirOnMacOrUnix)
{
    const auto spec = make_spec(0, "/opt/llama-lib");
    const auto env = spec.environment();
    EXPECT_EQ(env.value("LLAMA_ARG_CORS_ORIGINS"), "localhost");
#ifdef Q_OS_MACOS
    EXPECT_TRUE(env.value("DYLD_LIBRARY_PATH").startsWith("/opt/llama-lib"));
#elif defined(Q_OS_WIN)
    EXPECT_TRUE(env.value("PATH").startsWith("/opt/llama-lib"));
#else
    EXPECT_TRUE(env.value("LD_LIBRARY_PATH").startsWith("/opt/llama-lib"));
#endif
}

TEST(TestLlamaServerProcessSpec, setsOptimisationEnvFromOptions)
{
    auto options = base_options();
    options.n_gpu_layers = "auto";
    options.flash_attn = "auto";
    options.cache_type_k = "q8_0";
    options.cache_type_v = "q8_0";
    options.cache_reuse = 256;
    options.fit = true;
    options.apply_fit = true;
    options.load_mode = "mmap+mlock";
    options.cpu_moe = true;
    options.n_cpu_moe = 4;
    options.threads = 8;
    options.batch_size = 2048;
    options.ubatch_size = 512;
    const auto env = mp::LlamaServerProcessSpec{options}.environment();
    EXPECT_EQ(env.value("LLAMA_ARG_FLASH_ATTN"), "auto");
    EXPECT_EQ(env.value("LLAMA_ARG_CACHE_TYPE_K"), "q8_0");
    EXPECT_EQ(env.value("LLAMA_ARG_CACHE_TYPE_V"), "q8_0");
    EXPECT_EQ(env.value("LLAMA_ARG_CACHE_REUSE"), "256");
    EXPECT_EQ(env.value("LLAMA_ARG_FIT"), "on");
    EXPECT_EQ(env.value("LLAMA_ARG_LOAD_MODE"), "mmap+mlock");
    EXPECT_EQ(env.value("LLAMA_ARG_CPU_MOE"), "1");
    EXPECT_EQ(env.value("LLAMA_ARG_N_CPU_MOE"), "4");
    EXPECT_EQ(env.value("LLAMA_ARG_THREADS"), "8");
    EXPECT_EQ(env.value("LLAMA_ARG_BATCH"), "2048");
    EXPECT_EQ(env.value("LLAMA_ARG_UBATCH"), "512");
    EXPECT_EQ(mp::LlamaServerProcessSpec{options}.arguments().at(
                  mp::LlamaServerProcessSpec{options}.arguments().indexOf("--n-gpu-layers") + 1),
              "auto");
}
