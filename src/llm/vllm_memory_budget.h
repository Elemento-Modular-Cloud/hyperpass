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

#pragma once

namespace multipass
{

/// Floor for auto `--gpu-memory-utilization` so tiny models still get a usable KV pool.
inline constexpr double vllm_util_floor = 0.10;

/// CUDA / engine overhead reserved on top of weights + KV.
inline constexpr long long vllm_runtime_overhead_bytes = 1536LL * 1024 * 1024; // 1.5 GiB

/// 0.80 on aarch64/unified (GB10); 0.90 elsewhere.
double vllm_host_util_cap();

/// Rough KV bytes for a context length (same scale as llama estimate_claim at f16).
long long vllm_kv_budget_bytes(int max_model_len);

/// Weights + KV + runtime overhead for one 1:1 vLLM process.
long long vllm_budget_bytes(long long size_bytes, int max_model_len);

/// Model-fit util in [vllm_util_floor, host_cap].
/// When gpu_total_bytes <= 0, returns host_cap (safe fixed default).
/// When host_cap <= 0, uses vllm_host_util_cap().
double estimate_vllm_gpu_memory_utilization(long long size_bytes,
                                            int max_model_len,
                                            long long gpu_total_bytes,
                                            double host_cap = 0);

/// What vLLM actually reserves: util × GPU/UMA pool. Falls back to budget when total unknown.
long long vllm_claim_bytes(double gpu_memory_utilization,
                           long long gpu_total_bytes,
                           long long size_bytes,
                           int max_model_len);

/// Probe total GPU memory: nvidia-smi, then host RAM (unified-memory fallback). 0 if unknown.
long long probe_gpu_total_bytes();

} // namespace multipass
