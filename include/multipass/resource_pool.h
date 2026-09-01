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

#include <multipass/memory_size.h>

#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace multipass
{

enum class WorkloadKind
{
    vm,
    llm
};

enum class MemoryPolicy
{
    strict,
    best_effort
};

struct ResourceClaim
{
    std::string name;
    WorkloadKind kind{WorkloadKind::vm};
    MemorySize memory{};
    int cpus{0};
};

struct TryClaimResult
{
    bool accepted{true};
    std::string message;
};

class ResourcePool
{
public:
    ResourcePool(MemorySize host_memory, int host_cpus);

    void set_memory_reserve(MemorySize reserve);
    void set_memory_policy(MemoryPolicy policy);
    void set_host_memory(MemorySize host_memory);
    void set_host_cpus(int host_cpus);

    [[nodiscard]] MemorySize host_memory() const;
    [[nodiscard]] MemorySize memory_reserve() const;
    [[nodiscard]] MemorySize memory_capacity() const;
    [[nodiscard]] MemorySize memory_claimed() const;
    [[nodiscard]] MemorySize memory_available() const;
    [[nodiscard]] MemoryPolicy memory_policy() const;

    [[nodiscard]] int host_cpus() const;
    [[nodiscard]] int cpus_claimed() const;

    [[nodiscard]] bool has_claim(const std::string& name) const;
    [[nodiscard]] std::vector<ResourceClaim> claims() const;

    TryClaimResult try_claim(const std::string& name,
                             WorkloadKind kind,
                             MemorySize memory,
                             int cpus);
    /** True if `memory` would fit without mutating claims (strict) or a warning (best-effort). */
    [[nodiscard]] TryClaimResult check_admit(MemorySize memory, int cpus) const;
    void force_claim(const std::string& name, WorkloadKind kind, MemorySize memory, int cpus);
    void release(const std::string& name);

    /** Unload LLM claims first (largest first) until `needed` fits, or nothing left to preempt. */
    std::vector<std::string> preempt_llms_to_free(MemorySize needed);

private:
    TryClaimResult try_claim_locked(const std::string& name,
                                    WorkloadKind kind,
                                    MemorySize memory,
                                    int cpus,
                                    bool force);

    MemorySize host_memory_;
    MemorySize reserve_;
    MemoryPolicy policy_{MemoryPolicy::strict};
    int host_cpus_{1};
    std::unordered_map<std::string, ResourceClaim> claims_;
    mutable std::mutex mutex;
};

const char* workload_kind_name(WorkloadKind kind);

} // namespace multipass
