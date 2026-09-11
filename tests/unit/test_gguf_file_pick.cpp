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

#include "gguf_file_pick.h"

#include <QFile>
#include <QStringList>
#include <QTemporaryDir>

namespace mp = multipass;
using namespace testing;

TEST(TestGgufFilePick, skipsMmprojWhenPickingMainWeights)
{
    const QStringList files{"gemma-4-E2B-it-mmproj.gguf", "gemma-4-E2B-it-qat-q4_0.gguf"};
    EXPECT_EQ(mp::pick_gguf_file(files, "Q4_0"), "gemma-4-E2B-it-qat-q4_0.gguf");
    EXPECT_EQ(mp::pick_mmproj_file(files), "gemma-4-E2B-it-mmproj.gguf");
}

TEST(TestGgufFilePick, doesNotFallBackToMmproj)
{
    const QStringList files{"gemma-4-E2B-it-mmproj.gguf"};
    EXPECT_TRUE(mp::pick_gguf_file(files, {}).isEmpty());
    EXPECT_EQ(mp::pick_mmproj_file(files), "gemma-4-E2B-it-mmproj.gguf");
}

TEST(TestGgufFilePick, skipsShardedGgufs)
{
    const QStringList files{"model-00001-of-00002.gguf", "model-Q4_K_M.gguf"};
    EXPECT_EQ(mp::pick_gguf_file(files, {}), "model-Q4_K_M.gguf");
}

TEST(TestGgufFilePick, detectsProjectorNames)
{
    EXPECT_TRUE(mp::is_mmproj_gguf("foo-mmproj.gguf"));
    EXPECT_TRUE(mp::is_mmproj_gguf("Foo-MM-PROJ.gguf"));
    EXPECT_TRUE(mp::is_mmproj_gguf("llava-clip.gguf"));
    EXPECT_FALSE(mp::is_mmproj_gguf("Llama-3.2-3B-Instruct-Q4_K_M.gguf"));
}

TEST(TestGgufFilePick, findsSiblingMmproj)
{
    QTemporaryDir dir;
    ASSERT_TRUE(dir.isValid());
    const auto main = dir.filePath("model-q4_0.gguf");
    const auto proj = dir.filePath("model-mmproj.gguf");
    QFile f1{main};
    QFile f2{proj};
    ASSERT_TRUE(f1.open(QIODevice::WriteOnly));
    ASSERT_TRUE(f2.open(QIODevice::WriteOnly));
    f1.close();
    f2.close();

    EXPECT_EQ(QFileInfo{mp::find_sibling_mmproj(main)}.canonicalFilePath(),
              QFileInfo{proj}.canonicalFilePath());
    EXPECT_TRUE(mp::find_sibling_mmproj(proj).isEmpty());
}
