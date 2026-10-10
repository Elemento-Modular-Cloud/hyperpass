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

#include "gguf_kv_geometry.h"

#include <QFile>

#include <algorithm>
#include <cstring>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace mp = multipass;

namespace
{
enum class GgufType : uint32_t
{
    uint8 = 0,
    int8 = 1,
    uint16 = 2,
    int16 = 3,
    uint32 = 4,
    int32 = 5,
    float32 = 6,
    bool_ = 7,
    string = 8,
    array = 9,
    uint64 = 10,
    int64 = 11,
    float64 = 12,
};

struct Cursor
{
    const uint8_t* p{nullptr};
    const uint8_t* end{nullptr};

    [[nodiscard]] bool need(size_t n) const
    {
        return p && end && static_cast<size_t>(end - p) >= n;
    }

    template <typename T>
    [[nodiscard]] bool read_pod(T& out)
    {
        if (!need(sizeof(T)))
            return false;
        std::memcpy(&out, p, sizeof(T));
        p += sizeof(T);
        return true;
    }

    [[nodiscard]] bool read_string(std::string& out)
    {
        uint64_t len = 0;
        if (!read_pod(len) || len > static_cast<uint64_t>(end - p))
            return false;
        out.assign(reinterpret_cast<const char*>(p), static_cast<size_t>(len));
        p += static_cast<size_t>(len);
        return true;
    }
};

[[nodiscard]] size_t scalar_size(GgufType type)
{
    switch (type)
    {
    case GgufType::uint8:
    case GgufType::int8:
    case GgufType::bool_:
        return 1;
    case GgufType::uint16:
    case GgufType::int16:
        return 2;
    case GgufType::uint32:
    case GgufType::int32:
    case GgufType::float32:
        return 4;
    case GgufType::uint64:
    case GgufType::int64:
    case GgufType::float64:
        return 8;
    default:
        return 0;
    }
}

struct MetaValue
{
    GgufType type{GgufType::uint32};
    std::vector<uint8_t> bytes; // scalar payload or packed array scalars
    std::vector<std::string> strings;
    GgufType array_type{GgufType::uint32};
    uint64_t array_count{0};
};

[[nodiscard]] std::optional<uint64_t> as_u64(const MetaValue& v)
{
    auto take = [&](auto x) -> uint64_t { return static_cast<uint64_t>(x); };
    if (v.bytes.empty())
        return std::nullopt;
    switch (v.type)
    {
    case GgufType::uint8:
        return take(*reinterpret_cast<const uint8_t*>(v.bytes.data()));
    case GgufType::int8:
        return take(*reinterpret_cast<const int8_t*>(v.bytes.data()));
    case GgufType::uint16:
        return take(*reinterpret_cast<const uint16_t*>(v.bytes.data()));
    case GgufType::int16:
        return take(*reinterpret_cast<const int16_t*>(v.bytes.data()));
    case GgufType::uint32:
        return take(*reinterpret_cast<const uint32_t*>(v.bytes.data()));
    case GgufType::int32:
        return take(*reinterpret_cast<const int32_t*>(v.bytes.data()));
    case GgufType::uint64:
        return *reinterpret_cast<const uint64_t*>(v.bytes.data());
    case GgufType::int64:
        return take(*reinterpret_cast<const int64_t*>(v.bytes.data()));
    default:
        return std::nullopt;
    }
}

[[nodiscard]] bool read_value(Cursor& c, GgufType type, MetaValue& out)
{
    out.type = type;
    out.bytes.clear();
    out.strings.clear();
    if (type == GgufType::string)
    {
        std::string s;
        if (!c.read_string(s))
            return false;
        out.strings.push_back(std::move(s));
        return true;
    }
    if (type == GgufType::array)
    {
        uint32_t subtype = 0;
        uint64_t count = 0;
        if (!c.read_pod(subtype) || !c.read_pod(count))
            return false;
        out.array_type = static_cast<GgufType>(subtype);
        out.array_count = count;
        if (out.array_type == GgufType::string)
        {
            out.strings.reserve(static_cast<size_t>(count));
            for (uint64_t i = 0; i < count; ++i)
            {
                std::string s;
                if (!c.read_string(s))
                    return false;
                out.strings.push_back(std::move(s));
            }
            return true;
        }
        const auto elem = scalar_size(out.array_type);
        if (elem == 0)
            return false;
        const auto nbytes = elem * static_cast<size_t>(count);
        if (!c.need(nbytes))
            return false;
        out.bytes.assign(c.p, c.p + nbytes);
        c.p += nbytes;
        return true;
    }
    const auto n = scalar_size(type);
    if (n == 0 || !c.need(n))
        return false;
    out.bytes.assign(c.p, c.p + n);
    c.p += n;
    return true;
}

[[nodiscard]] std::optional<uint64_t> meta_u64(const std::unordered_map<std::string, MetaValue>& kv,
                                               const std::string& key)
{
    const auto it = kv.find(key);
    if (it == kv.end())
        return std::nullopt;
    return as_u64(it->second);
}

[[nodiscard]] std::optional<std::string> meta_string(const std::unordered_map<std::string, MetaValue>& kv,
                                                     const std::string& key)
{
    const auto it = kv.find(key);
    if (it == kv.end() || it->second.strings.empty())
        return std::nullopt;
    return it->second.strings.front();
}

[[nodiscard]] int count_kv_layers(const std::unordered_map<std::string, MetaValue>& kv,
                                  const std::string& arch,
                                  int n_layer_all,
                                  int n_nextn)
{
    const auto n_layer = std::max(0, n_layer_all - std::max(0, n_nextn));
    if (n_layer <= 0)
        return 0;

    const auto recr_key = arch + ".attention.recurrent_layers";
    if (const auto it = kv.find(recr_key); it != kv.end() && it->second.type == GgufType::array)
    {
        const auto& v = it->second;
        int full = 0;
        if (v.array_type == GgufType::bool_ || v.array_type == GgufType::uint8 ||
            v.array_type == GgufType::int8)
        {
            const auto n = std::min<size_t>(v.bytes.size(), static_cast<size_t>(n_layer));
            for (size_t i = 0; i < n; ++i)
            {
                if (v.bytes[i] == 0)
                    ++full;
            }
            // MTP / next-n blocks are dense attention in llama.cpp.
            full += std::max(0, n_nextn);
            return full > 0 ? full : n_layer;
        }
    }

    const auto interval_key = arch + ".full_attention_interval";
    uint32_t interval = 0;
    if (const auto iv = meta_u64(kv, interval_key))
        interval = static_cast<uint32_t>(*iv);
    const bool hybrid_arch = arch.find("qwen35") != std::string::npos ||
                             kv.find(arch + ".ssm.conv_kernel") != kv.end() ||
                             kv.find(arch + ".ssm.inner_size") != kv.end() || interval > 0;
    if (hybrid_arch)
    {
        if (interval == 0)
            interval = 4;
        int full = 0;
        for (int i = 0; i < n_layer; ++i)
        {
            if ((i + 1) % static_cast<int>(interval) == 0)
                ++full;
        }
        full += std::max(0, n_nextn);
        return full > 0 ? full : n_layer;
    }

    return n_layer_all;
}
} // namespace

long long mp::gguf_kv_bytes_per_token_f16(const GgufKvGeometry& g)
{
    if (g.n_layer_kv <= 0 || g.n_head_kv <= 0 || g.n_embd_head_k <= 0 || g.n_embd_head_v <= 0)
        return 0;
    // K and V each store n_head_kv * head_dim * 2 bytes (f16) per layer per token.
    const auto per_layer =
        static_cast<long long>(g.n_head_kv) *
        (static_cast<long long>(g.n_embd_head_k) + static_cast<long long>(g.n_embd_head_v)) * 2LL;
    return static_cast<long long>(g.n_layer_kv) * per_layer;
}

mp::GgufKvGeometry mp::read_gguf_kv_geometry(const std::string& path)
{
    GgufKvGeometry out;
    if (path.empty())
    {
        out.error = "empty path";
        return out;
    }

    QFile file{QString::fromStdString(path)};
    if (!file.open(QIODevice::ReadOnly))
    {
        out.error = "open failed";
        return out;
    }

    // Metadata is at the start; 8 MiB covers typical GGUF headers with arrays.
    constexpr qint64 k_max_header = 8LL * 1024 * 1024;
    const auto chunk = file.read(k_max_header);
    if (chunk.size() < 24)
    {
        out.error = "short file";
        return out;
    }

    Cursor c{reinterpret_cast<const uint8_t*>(chunk.constData()),
             reinterpret_cast<const uint8_t*>(chunk.constData()) + chunk.size()};

    char magic[4]{};
    if (!c.read_pod(magic) || std::memcmp(magic, "GGUF", 4) != 0)
    {
        out.error = "bad magic";
        return out;
    }
    uint32_t version = 0;
    uint64_t tensor_count = 0;
    uint64_t kv_count = 0;
    if (!c.read_pod(version) || version < 2 || version > 3)
    {
        out.error = "bad version";
        return out;
    }
    if (!c.read_pod(tensor_count) || !c.read_pod(kv_count) || kv_count > 4096)
    {
        out.error = "bad counts";
        return out;
    }

    std::unordered_map<std::string, MetaValue> kv;
    kv.reserve(static_cast<size_t>(kv_count));
    for (uint64_t i = 0; i < kv_count; ++i)
    {
        std::string key;
        uint32_t type_u = 0;
        if (!c.read_string(key) || !c.read_pod(type_u))
        {
            out.error = "kv key read failed";
            return out;
        }
        MetaValue value;
        if (!read_value(c, static_cast<GgufType>(type_u), value))
        {
            out.error = "kv value read failed for " + key;
            return out;
        }
        kv.emplace(std::move(key), std::move(value));
    }

    const auto arch = meta_string(kv, "general.architecture");
    if (!arch || arch->empty())
    {
        out.error = "missing architecture";
        return out;
    }
    out.architecture = *arch;

    const auto block_count = meta_u64(kv, out.architecture + ".block_count");
    if (!block_count || *block_count == 0 || *block_count > 512)
    {
        out.error = "bad block_count";
        return out;
    }

    auto head_kv = meta_u64(kv, out.architecture + ".attention.head_count_kv");
    if (!head_kv)
        head_kv = meta_u64(kv, out.architecture + ".attention.head_count");
    if (!head_kv || *head_kv == 0 || *head_kv > 256)
    {
        out.error = "bad head_count_kv";
        return out;
    }

    const auto head_count = meta_u64(kv, out.architecture + ".attention.head_count");
    const auto embd = meta_u64(kv, out.architecture + ".embedding_length");
    auto key_len = meta_u64(kv, out.architecture + ".attention.key_length");
    auto val_len = meta_u64(kv, out.architecture + ".attention.value_length");
    if (!key_len && embd && head_count && *head_count > 0)
        key_len = *embd / *head_count;
    if (!val_len)
        val_len = key_len;
    if (!key_len || !val_len || *key_len == 0 || *val_len == 0 || *key_len > 1024 || *val_len > 1024)
    {
        out.error = "bad head dims";
        return out;
    }

    int n_nextn = 0;
    if (const auto nextn = meta_u64(kv, out.architecture + ".nextn_predict_layers"))
        n_nextn = static_cast<int>(*nextn);

    out.n_layer_kv =
        count_kv_layers(kv, out.architecture, static_cast<int>(*block_count), n_nextn);
    out.n_head_kv = static_cast<int>(*head_kv);
    out.n_embd_head_k = static_cast<int>(*key_len);
    out.n_embd_head_v = static_cast<int>(*val_len);
    out.ok = out.n_layer_kv > 0 && gguf_kv_bytes_per_token_f16(out) > 0;
    if (!out.ok)
        out.error = "geometry incomplete";
    return out;
}
