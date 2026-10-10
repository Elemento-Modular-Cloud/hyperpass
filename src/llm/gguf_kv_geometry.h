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

#pragma once

#include <cstdint>
#include <string>

namespace multipass
{

/// Attention-KV geometry derived from GGUF metadata (token-growing cache only).
struct GgufKvGeometry
{
    std::string architecture;
    int n_layer_kv{0};     ///< layers that allocate per-token K/V
    int n_head_kv{0};
    int n_embd_head_k{0};
    int n_embd_head_v{0};
    bool ok{false};
    /// Populated when ok is false (unit tests / diagnostics).
    std::string error;
};

/// Bytes of K+V cache per token at f16 (before cache-type scale).
[[nodiscard]] long long gguf_kv_bytes_per_token_f16(const GgufKvGeometry& g);

/// Read enough GGUF metadata to size the attention KV cache. Returns !ok on failure.
[[nodiscard]] GgufKvGeometry read_gguf_kv_geometry(const std::string& path);

} // namespace multipass
