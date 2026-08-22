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

#include <algorithm>
#include <array>
#include <cctype>
#include <vector>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "runtime-info";

struct Keys
{
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

// Escaping matches the echo…eval wrapper: \$ → $, \" → " inside the eval'd string.
// Use %.0f so awk does not clamp totals ≥2GiB via printf %d.
struct MetricsProfile
{
    const char* mem_usage;
    const char* mem_total;
    const char* disk_usage;
    const char* disk_total;
    const char* cpus;
    const char* uptime;
};

// util-linux / GNU coreutils (Ubuntu, Debian, Fedora, RHEL-ish, openSUSE, Ubuntu Core, …)
constexpr MetricsProfile gnu_profile{
    /* mem_usage */ R"(free -b | grep 'Mem:' | awk '{printf \$3}')",
    /* mem_total */ R"(free -b | grep 'Mem:' | awk '{printf \$2}')",
    /* disk_usage */
    R"(lsblk -b -n -o FSUSED,FSTYPE,MOUNTPOINT -e7 2>/dev/null | )"
    R"(awk '\$2!=\"\" && \$2!=\"swap\" && \$3!=\"\"{sum+=\$1} END{printf \"%.0f\", sum+0}')",
    /* disk_total */
    R"(lsblk -b -d -n -o SIZE -e7 2>/dev/null | awk '{sum+=\$1} END{printf \"%.0f\", sum+0}')",
    /* cpus */ "nproc",
    /* uptime */ "uptime -p | tail -c+4",
};

// BusyBox / Alpine: no bash, no free -b, often no nproc / lsblk FSUSED / uptime -p.
constexpr MetricsProfile busybox_profile{
    /* mem_usage */
    R"(awk '/^MemTotal:/ {t=\$2} /^MemAvailable:/ {a=\$2} /^MemFree:/ {f=\$2} )"
    R"( /^Buffers:/ {b=\$2} /^Cached:/ {c=\$2} )"
    R"(END{ if (a != \"\") printf \"%.0f\", (t-a)*1024; else printf \"%.0f\", (t-f-b-c)*1024 }' )"
    R"(/proc/meminfo)",
    /* mem_total */ R"(awk '/^MemTotal:/ {printf \"%.0f\", \$2*1024}' /proc/meminfo)",
    /* disk_usage */ R"(df -k / 2>/dev/null | awk 'NR==2{printf \"%.0f\", \$3*1024}')",
    /* disk_total */ R"(df -k / 2>/dev/null | awk 'NR==2{printf \"%.0f\", \$2*1024}')",
    /* cpus */
    R"(getconf _NPROCESSORS_ONLN 2>/dev/null || grep -c ^processor /proc/cpuinfo)",
    /* uptime */ R"(awk '{printf \"%d minutes\", int(\$1/60)}' /proc/uptime)",
};

std::string normalize_os(std::string os)
{
    for (char& c : os)
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    os.erase(std::remove(os.begin(), os.end(), ' '), os.end());
    return os;
}

const MetricsProfile& profile_for(const std::string& os)
{
    const auto id = normalize_os(os);
    if (id.find("alpine") != std::string::npos)
        return busybox_profile;
    return gnu_profile;
}

std::string single_quote_for_shell(const std::string& in)
{
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

std::string with_timeout(const std::string& inner)
{
    // Always sh: Alpine and other minimal images often have no bash. SSH read timeout after connect
    // is effectively infinite — cap the guest probe so a stuck tool cannot wedge multipassd.
    return fmt::format("timeout 12 sh -c {}", single_quote_for_shell(inner));
}

std::string build_composite_cmd(const MetricsProfile& profile, bool parallelize)
{
    static constexpr auto key_val_cmd = R"-(echo {}: "$(eval "{}")")-";

    const std::array key_cmds_pairs{
        std::pair{Keys::loadavg_key, "cat /proc/loadavg | cut -d ' ' -f1-3"},
        std::pair{Keys::mem_usage_key, profile.mem_usage},
        std::pair{Keys::mem_total_key, profile.mem_total},
        std::pair{Keys::disk_usage_key, profile.disk_usage},
        std::pair{Keys::disk_total_key, profile.disk_total},
        std::pair{Keys::cpus_key, profile.cpus},
        std::pair{Keys::cpu_times_key, "head -n1 /proc/stat"},
        std::pair{Keys::uptime_key, profile.uptime},
        std::pair{Keys::current_release_key,
                  R"(cat /etc/os-release | grep 'PRETTY_NAME' | cut -d \\\" -f2)"}};

    std::vector<std::string> cmds;
    cmds.reserve(key_cmds_pairs.size());
    for (const auto& [key, cmd] : key_cmds_pairs)
        cmds.push_back(fmt::format(key_val_cmd, key, cmd));

    const auto inner = parallelize ? fmt::format("{} & wait", fmt::join(cmds, "& "))
                                   : fmt::to_string(fmt::join(cmds, "; "));
    return with_timeout(inner);
}

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
                                                          const std::string& os,
                                                          bool parallelize)
{
    try
    {
        const auto cmd = build_composite_cmd(profile_for(os), parallelize);
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
                  "Failed to retrieve runtime info for '{}' (os='{}'): {}",
                  vm.get_name(),
                  os,
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
