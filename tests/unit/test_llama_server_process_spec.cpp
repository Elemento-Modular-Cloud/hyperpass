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
mp::LlamaServerProcessSpec make_spec(int max_tokens = 0, QString library_dir = {})
{
    return mp::LlamaServerProcessSpec{"/opt/llama-server",
                                      "/models/nemotron.gguf",
                                      "nemotron-abc",
                                      52792,
                                      8192,
                                      99,
                                      max_tokens,
                                      std::move(library_dir)};
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

TEST(TestLlamaServerProcessSpec, argumentsIncludeNPredictWhenCapped)
{
    const auto spec = make_spec(512);
    EXPECT_TRUE(spec.arguments().contains("--n-predict"));
    EXPECT_TRUE(spec.arguments().contains("512"));
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
