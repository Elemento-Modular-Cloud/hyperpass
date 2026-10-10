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
 */

#include "common.h"

#include "gguf_kv_geometry.h"
#include "llm_memory_claim.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>

#include <cstring>
#include <string>
#include <vector>

namespace mp = multipass;
using namespace testing;

namespace
{
constexpr long long gib = 1024LL * 1024 * 1024;

void append_pod(std::vector<uint8_t>& out, const auto& value)
{
    const auto* p = reinterpret_cast<const uint8_t*>(&value);
    out.insert(out.end(), p, p + sizeof(value));
}

void append_string(std::vector<uint8_t>& out, const std::string& s)
{
    const uint64_t len = s.size();
    append_pod(out, len);
    out.insert(out.end(), s.begin(), s.end());
}

void append_kv_u32(std::vector<uint8_t>& out, const std::string& key, uint32_t value)
{
    append_string(out, key);
    const uint32_t type = 4; // UINT32
    append_pod(out, type);
    append_pod(out, value);
}

void append_kv_string(std::vector<uint8_t>& out, const std::string& key, const std::string& value)
{
    append_string(out, key);
    const uint32_t type = 8; // STRING
    append_pod(out, type);
    append_string(out, value);
}

QString write_qwen35moe_gguf(const QTemporaryDir& dir)
{
    // 48 layers, interval 4 → 12 full-attention layers; 2 KV heads × 256 dim.
    std::vector<uint8_t> buf;
    buf.insert(buf.end(), {'G', 'G', 'U', 'F'});
    const uint32_t version = 3;
    const uint64_t tensor_count = 0;
    const uint64_t kv_count = 7;
    append_pod(buf, version);
    append_pod(buf, tensor_count);
    append_pod(buf, kv_count);
    append_kv_string(buf, "general.architecture", "qwen35moe");
    append_kv_u32(buf, "qwen35moe.block_count", 48);
    append_kv_u32(buf, "qwen35moe.embedding_length", 4096);
    append_kv_u32(buf, "qwen35moe.attention.head_count", 32);
    append_kv_u32(buf, "qwen35moe.attention.head_count_kv", 2);
    append_kv_u32(buf, "qwen35moe.attention.key_length", 256);
    append_kv_u32(buf, "qwen35moe.attention.value_length", 256);

    const auto path = dir.filePath("qwen35moe-test.gguf");
    QFile f{path};
    EXPECT_TRUE(f.open(QIODevice::WriteOnly));
    EXPECT_EQ(f.write(reinterpret_cast<const char*>(buf.data()),
                      static_cast<qint64>(buf.size())),
              static_cast<qint64>(buf.size()));
    f.close();
    return path;
}
} // namespace

TEST(TestGgufKvGeometry, qwen35moeHybridCountsFullAttentionLayersOnly)
{
    QTemporaryDir dir;
    ASSERT_TRUE(dir.isValid());
    const auto path = write_qwen35moe_gguf(dir).toStdString();

    const auto geo = mp::read_gguf_kv_geometry(path);
    ASSERT_TRUE(geo.ok) << geo.error << " path=" << path;
    EXPECT_EQ(geo.architecture, "qwen35moe");
    EXPECT_EQ(geo.n_layer_kv, 12);
    EXPECT_EQ(geo.n_head_kv, 2);
    EXPECT_EQ(geo.n_embd_head_k, 256);
    EXPECT_EQ(geo.n_embd_head_v, 256);
    // 12 * 2 * (256+256) * 2 = 24576 bytes/token at f16 (~24 KiB).
    EXPECT_EQ(mp::gguf_kv_bytes_per_token_f16(geo), 24576);
}

TEST(TestGgufKvGeometry, llamaClaimUsesGgufGeometryNotDenseHeuristic)
{
    QTemporaryDir dir;
    ASSERT_TRUE(dir.isValid());
    const auto path = write_qwen35moe_gguf(dir).toStdString();

    constexpr int ctx = 1024000;
    const auto with_geo =
        mp::estimate_llama_claim_bytes(40 * gib, ctx, 1, "q8_0", "q8_0", path);
    const auto fallback =
        mp::estimate_llama_claim_bytes(40 * gib, ctx, 1, "q8_0", "q8_0", {});

    // Dense heuristic (~0.25 MiB/token × 0.5) blows past 100 GiB of KV alone.
    EXPECT_GT(fallback, 150 * gib);
    // Architecture path: 40 GiB weights + ~12.6 GiB KV (q8) + 0.5 GiB overhead.
    EXPECT_LT(with_geo, 60 * gib);
    EXPECT_GT(with_geo, 45 * gib);
    EXPECT_LT(with_geo, fallback / 2);
}
