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
#include "temp_dir.h"

#include "mlx_server_process_spec.h"

#include <QDir>

namespace mp = multipass;
namespace mpt = multipass::test;
using namespace testing;

TEST(TestMlxServerProcessSpec, pythonLaunchUsesModule)
{
    mp::MlxServerOptions options;
    options.program = "/usr/bin/python3";
    options.model_path = "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit";
    options.port = 12345;
    const mp::MlxServerProcessSpec spec{options};
    EXPECT_EQ(spec.arguments(),
              QStringList({"-m",
                           "mlx_lm.server",
                           "--host",
                           "127.0.0.1",
                           "--port",
                           "12345",
                           "--model",
                           "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
                           "--use-default-chat-template"}));
}

TEST(TestMlxServerProcessSpec, environmentCreatesCacheAndSetsHfVars)
{
    mpt::TempDir dir;
    mp::MlxServerOptions options;
    options.program = "mlx_lm.server";
    options.model_path = "org/model";
    options.port = 9;
    options.hf_cache_dir = dir.filePath("hf-cache");
    options.hf_token = "hf_secret";

    const mp::MlxServerProcessSpec spec{options};
    EXPECT_TRUE(QDir{options.hf_cache_dir}.exists());
    const auto env = spec.environment();
    EXPECT_EQ(env.value("HF_HUB_CACHE"), options.hf_cache_dir);
    EXPECT_EQ(env.value("HF_TOKEN"), "hf_secret");
}
