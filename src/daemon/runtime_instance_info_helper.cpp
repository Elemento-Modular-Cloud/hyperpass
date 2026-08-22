/*
 * Copyright (C) Canonical, Ltd.
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

#include "runtime_instance_info_helper.h"

#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/rpc/multipass.grpc.pb.h>
#include <multipass/utils.h>
#include <multipass/virtual_machine.h>

#include <yaml-cpp/yaml.h>

#include <array>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "runtime-info";

struct Keys
{
public:
    static constexpr auto loadavg_key = "loadavg";
    static constexpr auto mem_usage_key = "mem_usage";
    static constexpr auto mem_total_key = "mem_total";
    static constexpr auto disk_usage_key = "disk_usage";
    static constexpr auto disk_total_key = "disk_total";
    static constexpr auto cpus_key = "cpus";
    static constexpr auto cpu_times_key = "cpu_times";
    static constexpr auto uptime_key = "uptime";
    static constexpr auto current_release_key = "current_release";
};

std::string single_quote_for_shell(const std::string& in)
{
    // Wrap in single quotes; encode embedded ' as: '\''
    std::string out;
    out.reserve(in.size() + 2);
    out.push_back('\'');
    for (char c : in)
    {
        if (c == '\'')
            out += "'\\''";
        else
            out.push_back(c);
    }
    out.push_back('\'');
    return out;
}

struct Cmds
{
private:
    static constexpr auto key_val_cmd = R"-(echo {}: "$(eval "{}")")-";
    // Keep disk probes as short pipelines (no nested bash -c, no full-table df). Escaping matches
    // the echo…eval wrapper: \$ → $, \" → " inside the eval'd string. Use %.0f so awk does not
    // clamp totals ≥2GiB to INT_MAX via printf %d. Avoid `df` over all mounts — that can block
    // forever on a stuck filesystem while several VMs are still booting.
    static constexpr auto disk_usage_cmd =
        R"(lsblk -b -n -o FSUSED,FSTYPE,MOUNTPOINT -e7 2>/dev/null | )"
        R"(awk '\$2!=\"\" && \$2!=\"swap\" && \$3!=\"\"{sum+=\$1} END{printf \"%.0f\", sum+0}')";
    static constexpr auto disk_total_cmd =
        R"(lsblk -b -d -n -o SIZE -e7 2>/dev/null | )"
        R"(awk '{sum+=\$1} END{printf \"%.0f\", sum+0}')";
    static constexpr std::array key_cmds_pairs{
        std::pair{Keys::loadavg_key, "cat /proc/loadavg | cut -d ' ' -f1-3"},
        std::pair{Keys::mem_usage_key, R"(free -b | grep 'Mem:' | awk '{printf \$3}')"},
        std::pair{Keys::mem_total_key, R"(free -b | grep 'Mem:' | awk '{printf \$2}')"},
        std::pair{Keys::disk_usage_key, disk_usage_cmd},
        std::pair{Keys::disk_total_key, disk_total_cmd},
        std::pair{Keys::cpus_key, "nproc"},
        std::pair{Keys::cpu_times_key, "head -n1 /proc/stat"},
        std::pair{Keys::uptime_key, "uptime -p | tail -c+4"},
        std::pair{Keys::current_release_key,
                  R"(cat /etc/os-release | grep 'PRETTY_NAME' | cut -d \\\" -f2)"}};

    inline static const std::array cmds = [] {
        constexpr auto n = key_cmds_pairs.size();
        std::array<std::string, key_cmds_pairs.size()> ret;
        for (std::size_t i = 0; i < n; ++i)
        {
            const auto [key, cmd] = key_cmds_pairs[i];
            ret[i] = fmt::format(key_val_cmd, key, cmd);
        }

        return ret;
    }();

    // SSH read timeout after connect is effectively infinite. Cap the whole guest probe so a stuck
    // lsblk/df/free cannot wedge multipassd's RPC/Qt thread (which makes list/info/version hang).
    static std::string with_timeout(const std::string& inner)
    {
        return fmt::format("timeout 12 bash -c {}", single_quote_for_shell(inner));
    }

public:
    inline static const std::string sequential_composite_cmd =
        with_timeout(fmt::to_string(fmt::join(cmds, "; ")));
    inline static const std::string parallel_composite_cmd =
        with_timeout(fmt::format("{} & wait", fmt::join(cmds, "& ")));
};

// yaml-cpp turns YAML null into the string "null" for .as<std::string>() without a fallback.
std::string metric_or_empty(const YAML::Node& node)
{
    if (!node || node.IsNull())
        return {};
    auto value = node.as<std::string>("");
    return value == "null" ? std::string{} : value;
}
} // namespace

void mp::RuntimeInstanceInfoHelper::populate_runtime_info(mp::VirtualMachine& vm,
                                                          mp::DetailedInfoItem* info,
                                                          mp::InstanceDetails* instance_info,
                                                          const std::string& original_release,
                                                          bool parallelize)
{
    try
    {
        const auto& cmd =
            parallelize ? Cmds::parallel_composite_cmd : Cmds::sequential_composite_cmd;
        auto results = YAML::Load(vm.ssh_exec(cmd, /* whisper = */ true));

        instance_info->set_load(metric_or_empty(results[Keys::loadavg_key]));
        instance_info->set_memory_usage(metric_or_empty(results[Keys::mem_usage_key]));
        info->set_memory_total(metric_or_empty(results[Keys::mem_total_key]));
        instance_info->set_disk_usage(metric_or_empty(results[Keys::disk_usage_key]));
        info->set_disk_total(metric_or_empty(results[Keys::disk_total_key]));
        info->set_cpu_count(metric_or_empty(results[Keys::cpus_key]));
        instance_info->set_cpu_times(metric_or_empty(results[Keys::cpu_times_key]));
        // In some older versions of Ubuntu, "uptime -p" prints only "up" right after startup. In
        // those cases, results[Keys::uptime_key] is null.
        auto uptime = metric_or_empty(results[Keys::uptime_key]);
        instance_info->set_uptime(uptime.empty() ? "0 minutes" : uptime);

        auto current_release = metric_or_empty(results[Keys::current_release_key]);
        instance_info->set_current_release(!current_release.empty() ? current_release
                                                                    : original_release);
    }
    catch (const std::exception& e)
    {
        mpl::warn(category,
                  "Failed to retrieve runtime info for '{}': {}",
                  vm.get_name(),
                  e.what());
        instance_info->set_current_release(original_release);
    }

    try
    {
        auto management_ip = vm.management_ipv4();
        auto all_ipv4 = vm.get_all_ipv4();

        if (management_ip)
            instance_info->add_ipv4(management_ip->as_string());

        for (const auto& extra_ipv4 : all_ipv4)
            if (extra_ipv4 != management_ip)
                instance_info->add_ipv4(extra_ipv4.as_string());
    }
    catch (const std::exception& e)
    {
        mpl::warn(category, "Failed to retrieve IPv4 for '{}': {}", vm.get_name(), e.what());
    }
}
