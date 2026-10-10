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

#include <cstdint>
#include <string>
#include <unordered_map>
#include <unordered_set>

namespace multipass
{

/// Parse `nvidia-smi --query-compute-apps=pid,used_gpu_memory --format=csv,noheader,nounits`.
/// Values are MiB → returned map is PID → bytes.
std::unordered_map<std::int64_t, long long> parse_nvidia_smi_compute_apps_csv(const std::string& csv);

/// Sum GPU memory (bytes) for `root_pid` and its descendants from a PID→bytes map.
long long sum_gpu_memory_for_tree(std::int64_t root_pid,
                                  const std::unordered_map<std::int64_t, long long>& gpu_by_pid,
                                  const std::unordered_set<std::int64_t>& tree_pids);

/// Collect `root_pid` plus descendant PIDs via /proc (Linux). On failure, {root_pid} only.
std::unordered_set<std::int64_t> collect_process_tree_pids(std::int64_t root_pid);

/// Host RSS/PSS fallback for a process tree (bytes). 0 if unknown.
long long probe_host_memory_for_tree(const std::unordered_set<std::int64_t>& pids);

/// Best-effort measured reservation for an inference process tree (bytes).
/// Prefers nvidia-smi GPU memory; falls back to host PSS/RSS. 0 if unknown.
long long probe_session_memory_bytes(std::int64_t root_pid);

} // namespace multipass
