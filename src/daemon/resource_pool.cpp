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

#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/resource_pool.h>

#include <algorithm>
#include <vector>

namespace mp = multipass;

namespace
{
mp::MemorySize memory_claimed_locked(const std::unordered_map<std::string, mp::ResourceClaim>& claims)
{
    long long total = 0;
    for (const auto& [_, claim] : claims)
        total += claim.memory.in_bytes();
    return mp::MemorySize::from_bytes(total);
}

int cpus_claimed_locked(const std::unordered_map<std::string, mp::ResourceClaim>& claims)
{
    int total = 0;
    for (const auto& [_, claim] : claims)
        total += claim.cpus;
    return total;
}

mp::MemorySize capacity_locked(mp::MemorySize host, mp::MemorySize reserve)
{
    const auto host_bytes = host.in_bytes();
    const auto reserve_bytes = reserve.in_bytes();
    if (reserve_bytes >= host_bytes)
        return mp::MemorySize::from_bytes(0);
    return mp::MemorySize::from_bytes(host_bytes - reserve_bytes);
}
} // namespace

mp::ResourcePool::ResourcePool(MemorySize host_memory, int host_cpus)
    : host_memory_{host_memory},
      reserve_{MemorySize{default_host_memory_reserve}},
      host_cpus_{std::max(host_cpus, 1)}
{
}

void mp::ResourcePool::set_memory_reserve(MemorySize reserve)
{
    std::lock_guard lock{mutex};
    reserve_ = reserve;
}

void mp::ResourcePool::set_memory_policy(MemoryPolicy policy)
{
    std::lock_guard lock{mutex};
    policy_ = policy;
}

void mp::ResourcePool::set_host_memory(MemorySize host_memory)
{
    std::lock_guard lock{mutex};
    host_memory_ = host_memory;
}

void mp::ResourcePool::set_host_cpus(int host_cpus)
{
    std::lock_guard lock{mutex};
    host_cpus_ = std::max(host_cpus, 1);
}

mp::MemorySize mp::ResourcePool::host_memory() const
{
    std::lock_guard lock{mutex};
    return host_memory_;
}

mp::MemorySize mp::ResourcePool::memory_reserve() const
{
    std::lock_guard lock{mutex};
    return reserve_;
}

mp::MemorySize mp::ResourcePool::memory_capacity() const
{
    std::lock_guard lock{mutex};
    return capacity_locked(host_memory_, reserve_);
}

mp::MemorySize mp::ResourcePool::memory_claimed() const
{
    std::lock_guard lock{mutex};
    return memory_claimed_locked(claims_);
}

mp::MemorySize mp::ResourcePool::memory_available() const
{
    std::lock_guard lock{mutex};
    const auto cap = capacity_locked(host_memory_, reserve_).in_bytes();
    const auto used = memory_claimed_locked(claims_).in_bytes();
    return MemorySize::from_bytes(used >= cap ? 0 : cap - used);
}

mp::MemoryPolicy mp::ResourcePool::memory_policy() const
{
    std::lock_guard lock{mutex};
    return policy_;
}

int mp::ResourcePool::host_cpus() const
{
    std::lock_guard lock{mutex};
    return host_cpus_;
}

int mp::ResourcePool::cpus_claimed() const
{
    std::lock_guard lock{mutex};
    return cpus_claimed_locked(claims_);
}

bool mp::ResourcePool::has_claim(const std::string& name) const
{
    std::lock_guard lock{mutex};
    return claims_.contains(name);
}

std::vector<mp::ResourceClaim> mp::ResourcePool::claims() const
{
    std::lock_guard lock{mutex};
    std::vector<ResourceClaim> out;
    out.reserve(claims_.size());
    for (const auto& [_, claim] : claims_)
        out.push_back(claim);
    std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) { return a.name < b.name; });
    return out;
}

mp::TryClaimResult mp::ResourcePool::try_claim(const std::string& name,
                                               WorkloadKind kind,
                                               MemorySize memory,
                                               int cpus)
{
    std::lock_guard lock{mutex};
    return try_claim_locked(name, kind, memory, cpus, false);
}

mp::TryClaimResult mp::ResourcePool::check_admit(MemorySize memory, int cpus) const
{
    std::lock_guard lock{mutex};
    const auto cap = capacity_locked(host_memory_, reserve_).in_bytes();
    const auto used = memory_claimed_locked(claims_).in_bytes();
    const auto projected = used + memory.in_bytes();
    const bool unlimited = host_memory_.in_bytes() <= 0;
    (void)cpus;

    TryClaimResult result;
    if (!unlimited && projected > cap)
    {
        const auto available = used >= cap ? 0LL : cap - used;
        result.message = fmt::format(
            "Not enough host memory: requested {}, available {} (host {}, reserve {})",
            memory.human_readable(),
            MemorySize::from_bytes(available).human_readable(),
            host_memory_.human_readable(),
            reserve_.human_readable());
        if (policy_ == MemoryPolicy::strict)
        {
            result.accepted = false;
            return result;
        }
        result.accepted = true;
    }
    return result;
}

void mp::ResourcePool::force_claim(const std::string& name,
                                   WorkloadKind kind,
                                   MemorySize memory,
                                   int cpus)
{
    std::lock_guard lock{mutex};
    try_claim_locked(name, kind, memory, cpus, true);
}

void mp::ResourcePool::release(const std::string& name)
{
    std::lock_guard lock{mutex};
    claims_.erase(name);
}

std::vector<std::string> mp::ResourcePool::preempt_llms_to_free(MemorySize needed)
{
    std::lock_guard lock{mutex};
    std::vector<std::string> preempted;
    auto available = [&] {
        const auto cap = capacity_locked(host_memory_, reserve_).in_bytes();
        const auto used = memory_claimed_locked(claims_).in_bytes();
        return used >= cap ? 0LL : cap - used;
    };

    if (available() >= needed.in_bytes())
        return preempted;

    std::vector<ResourceClaim> llms;
    for (const auto& [_, claim] : claims_)
    {
        if (claim.kind == WorkloadKind::llm)
            llms.push_back(claim);
    }
    std::sort(llms.begin(), llms.end(), [](const auto& a, const auto& b) {
        return a.memory > b.memory;
    });

    for (const auto& claim : llms)
    {
        claims_.erase(claim.name);
        preempted.push_back(claim.name);
        if (available() >= needed.in_bytes())
            break;
    }
    return preempted;
}

mp::TryClaimResult mp::ResourcePool::try_claim_locked(const std::string& name,
                                                      WorkloadKind kind,
                                                      MemorySize memory,
                                                      int cpus,
                                                      bool force)
{
    long long existing = 0;
    if (auto it = claims_.find(name); it != claims_.end())
        existing = it->second.memory.in_bytes();

    const auto cap = capacity_locked(host_memory_, reserve_).in_bytes();
    const auto used = memory_claimed_locked(claims_).in_bytes();
    const auto projected = used - existing + memory.in_bytes();
    const bool unlimited = host_memory_.in_bytes() <= 0;

    TryClaimResult result;
    if (!force && !unlimited && projected > cap)
    {
        const auto available = used >= cap ? 0LL : cap - used + existing;
        result.message = fmt::format(
            "Not enough host memory for '{}': requested {}, available {} (host {}, reserve {})",
            name,
            memory.human_readable(),
            MemorySize::from_bytes(available).human_readable(),
            host_memory_.human_readable(),
            reserve_.human_readable());
        if (policy_ == MemoryPolicy::strict)
        {
            result.accepted = false;
            return result;
        }
        result.accepted = true;
    }

    claims_[name] = ResourceClaim{name, kind, memory, std::max(cpus, 0)};
    return result;
}

const char* mp::workload_kind_name(WorkloadKind kind)
{
    switch (kind)
    {
    case WorkloadKind::llm:
        return "llm";
    case WorkloadKind::vm:
    default:
        return "vm";
    }
}
