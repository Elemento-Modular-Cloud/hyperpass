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

#include <multipass/process/process_scan.h>

#include <gtest/gtest.h>

#ifndef MULTIPASS_PLATFORM_WINDOWS
#include <unistd.h>
#endif

namespace mpu = multipass::utils;

TEST(ProcessScan, parsesPsTable)
{
    const auto rows = mpu::parse_ps_table(
        "  60295 qemu-system-aarch64 -drive file=/tmp/foo.img,if=none,format=qcow2\n"
        "  12345 /opt/homebrew/bin/llama-server -m /models/a.gguf --port 7788 --alias gemma-abc\n");
    ASSERT_EQ(rows.size(), 2);
    EXPECT_EQ(rows[0].pid, 60295);
    EXPECT_TRUE(rows[0].command_line.contains("qemu-system-aarch64"));
    EXPECT_EQ(rows[1].pid, 12345);
    EXPECT_EQ(mpu::cli_flag_value(rows[1].command_line, {"--alias"}), "gemma-abc");
    EXPECT_EQ(mpu::cli_flag_value(rows[1].command_line, {"--port"}), "7788");
    EXPECT_EQ(mpu::cli_flag_value(rows[1].command_line, {"-m", "--model"}), "/models/a.gguf");
}

TEST(ProcessScan, pidIsAliveForSelf)
{
#ifndef MULTIPASS_PLATFORM_WINDOWS
    EXPECT_TRUE(mpu::pid_is_alive(getpid()));
#endif
    EXPECT_FALSE(mpu::pid_is_alive(0));
    EXPECT_FALSE(mpu::pid_is_alive(-1));
}
