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

#include <string>

namespace multipass
{

/// llama.cpp-style admit estimate: weights + KV(ctx) × scale + overhead.
/// `parallel` is accepted for API symmetry; llama-server splits `--ctx-size`
/// across slots, so total KV tracks ctx, not ctx×parallel.
/// When `gguf_path` is set, KV bytes/token come from GGUF attention geometry
/// (hybrid models only count full-attention layers). Otherwise falls back to
/// a dense-transformer heuristic (~0.25 MiB/token at f16).
long long estimate_llama_claim_bytes(long long size_bytes,
                                     int ctx_size,
                                     int parallel,
                                     const std::string& cache_type_k,
                                     const std::string& cache_type_v,
                                     const std::string& gguf_path = {});

/// MLX admit estimate: weights + fixed runtime overhead (no llama KV scale).
long long estimate_mlx_claim_bytes(long long size_bytes);

} // namespace multipass
