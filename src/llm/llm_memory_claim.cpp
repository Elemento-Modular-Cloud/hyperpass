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

#include "llm_memory_claim.h"

#include "gguf_kv_geometry.h"
#include "llm_load_params.h"

#include <algorithm>

namespace mp = multipass;

namespace
{
constexpr long long llama_runtime_overhead_bytes = 512LL * 1024 * 1024;
constexpr long long mlx_runtime_overhead_bytes = 768LL * 1024 * 1024;
/// Dense-transformer fallback when GGUF geometry is unavailable (~0.25 MiB/token at f16).
constexpr double fallback_kv_bytes_per_token_f16 = 2.0 * 1024.0 * 1024.0 / 8.0;

long long kv_bytes_for_tokens(int tokens, double bytes_per_token_f16, double scale)
{
    const auto tok = std::max(tokens, 2048);
    return static_cast<long long>(static_cast<double>(tok) * bytes_per_token_f16 * scale);
}
} // namespace

long long mp::estimate_llama_claim_bytes(long long size_bytes,
                                         int ctx_size,
                                         int parallel,
                                         const std::string& cache_type_k,
                                         const std::string& cache_type_v,
                                         const std::string& gguf_path)
{
    (void)parallel; // llama-server: --ctx-size is total, divided across --parallel slots.
    const auto weights = size_bytes > 0 ? size_bytes : 0LL;
    const auto scale = kv_cache_byte_scale(cache_type_k, cache_type_v);
    const auto tokens = ctx_size > 2048 ? ctx_size : 2048;

    double bytes_per_token = fallback_kv_bytes_per_token_f16;
    if (!gguf_path.empty())
    {
        if (const auto geo = read_gguf_kv_geometry(gguf_path); geo.ok)
        {
            const auto bpt = gguf_kv_bytes_per_token_f16(geo);
            if (bpt > 0)
                bytes_per_token = static_cast<double>(bpt);
        }
    }

    const auto kv = kv_bytes_for_tokens(tokens, bytes_per_token, scale);
    return weights + kv + llama_runtime_overhead_bytes;
}

long long mp::estimate_mlx_claim_bytes(long long size_bytes)
{
    return std::max(0LL, size_bytes) + mlx_runtime_overhead_bytes;
}
