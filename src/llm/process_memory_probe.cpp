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

#include "process_memory_probe.h"

#include <QDir>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>
#include <QString>
#include <QStringList>
#include <QTextStream>

#include <algorithm>
#include <sstream>

namespace mp = multipass;

namespace
{
constexpr long long mib = 1024LL * 1024;

std::int64_t read_ppid(std::int64_t pid)
{
    QFile status{QStringLiteral("/proc/%1/status").arg(pid)};
    if (!status.open(QIODevice::ReadOnly | QIODevice::Text))
        return -1;
    QTextStream in{&status};
    while (!in.atEnd())
    {
        const auto line = in.readLine();
        if (!line.startsWith(QLatin1String("PPid:")))
            continue;
        bool ok = false;
        const auto ppid = line.mid(QStringLiteral("PPid:").size()).trimmed().toLongLong(&ok);
        return ok ? ppid : -1;
    }
    return -1;
}

long long read_proc_bytes(std::int64_t pid)
{
    QFile rollup{QStringLiteral("/proc/%1/smaps_rollup").arg(pid)};
    if (rollup.open(QIODevice::ReadOnly | QIODevice::Text))
    {
        QTextStream in{&rollup};
        while (!in.atEnd())
        {
            const auto line = in.readLine();
            if (!line.startsWith(QLatin1String("Pss:")))
                continue;
            bool ok = false;
            const auto kib = line.mid(QStringLiteral("Pss:").size()).trimmed().section(' ', 0, 0).toLongLong(&ok);
            if (ok && kib > 0)
                return kib * 1024LL;
            break;
        }
    }

    QFile status{QStringLiteral("/proc/%1/status").arg(pid)};
    if (!status.open(QIODevice::ReadOnly | QIODevice::Text))
        return 0;
    QTextStream in{&status};
    while (!in.atEnd())
    {
        const auto line = in.readLine();
        if (!line.startsWith(QLatin1String("VmRSS:")))
            continue;
        bool ok = false;
        const auto kib = line.mid(QStringLiteral("VmRSS:").size()).trimmed().section(' ', 0, 0).toLongLong(&ok);
        return ok && kib > 0 ? kib * 1024LL : 0;
    }
    return 0;
}
} // namespace

std::unordered_map<std::int64_t, long long> mp::parse_nvidia_smi_compute_apps_csv(const std::string& csv)
{
    std::unordered_map<std::int64_t, long long> out;
    std::istringstream in{csv};
    std::string line;
    while (std::getline(in, line))
    {
        if (line.empty())
            continue;
        // "pid, used_gpu_memory [MiB]" or "123, 4567"
        const auto comma = line.find(',');
        if (comma == std::string::npos)
            continue;
        try
        {
            const auto pid = std::stoll(line.substr(0, comma));
            auto mem = line.substr(comma + 1);
            // trim
            while (!mem.empty() && (mem.front() == ' ' || mem.front() == '\t'))
                mem.erase(mem.begin());
            while (!mem.empty() && (mem.back() == ' ' || mem.back() == '\t' || mem.back() == '\r'))
                mem.pop_back();
            if (mem.empty() || mem == "[N/A]" || mem == "N/A")
                continue;
            const auto mib_val = std::stoll(mem);
            if (pid > 0 && mib_val > 0)
                out[pid] += mib_val * mib;
        }
        catch (const std::exception&)
        {
        }
    }
    return out;
}

long long mp::sum_gpu_memory_for_tree(std::int64_t root_pid,
                                      const std::unordered_map<std::int64_t, long long>& gpu_by_pid,
                                      const std::unordered_set<std::int64_t>& tree_pids)
{
    long long total = 0;
    for (const auto pid : tree_pids)
    {
        if (auto it = gpu_by_pid.find(pid); it != gpu_by_pid.end())
            total += it->second;
    }
    // EngineCore may outlive matching if tree scan missed it; also include exact root.
    if (total == 0)
    {
        if (auto it = gpu_by_pid.find(root_pid); it != gpu_by_pid.end())
            total = it->second;
    }
    return total;
}

std::unordered_set<std::int64_t> mp::collect_process_tree_pids(std::int64_t root_pid)
{
    std::unordered_set<std::int64_t> tree;
    if (root_pid <= 0)
        return tree;
    tree.insert(root_pid);

    QDir proc{QStringLiteral("/proc")};
    const auto entries = proc.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    // Parent→children map, then BFS from root.
    std::unordered_map<std::int64_t, std::vector<std::int64_t>> children;
    for (const auto& name : entries)
    {
        bool ok = false;
        const auto pid = name.toLongLong(&ok);
        if (!ok || pid <= 0)
            continue;
        const auto ppid = read_ppid(pid);
        if (ppid > 0)
            children[ppid].push_back(pid);
    }

    std::vector<std::int64_t> stack{root_pid};
    while (!stack.empty())
    {
        const auto cur = stack.back();
        stack.pop_back();
        auto it = children.find(cur);
        if (it == children.end())
            continue;
        for (const auto child : it->second)
        {
            if (tree.insert(child).second)
                stack.push_back(child);
        }
    }
    return tree;
}

long long mp::probe_host_memory_for_tree(const std::unordered_set<std::int64_t>& pids)
{
    long long total = 0;
    for (const auto pid : pids)
        total += read_proc_bytes(pid);
    return total;
}

long long mp::probe_session_memory_bytes(std::int64_t root_pid)
{
    if (root_pid <= 0)
        return 0;

    const auto tree = collect_process_tree_pids(root_pid);

    if (!QStandardPaths::findExecutable(QStringLiteral("nvidia-smi")).isEmpty())
    {
        QProcess proc;
        proc.start(QStringLiteral("nvidia-smi"),
                   {QStringLiteral("--query-compute-apps=pid,used_gpu_memory"),
                    QStringLiteral("--format=csv,noheader,nounits")});
        if (proc.waitForFinished(3000) && proc.exitCode() == 0)
        {
            const auto csv = proc.readAllStandardOutput().toStdString();
            const auto by_pid = parse_nvidia_smi_compute_apps_csv(csv);
            if (const auto gpu = sum_gpu_memory_for_tree(root_pid, by_pid, tree); gpu > 0)
                return gpu;
        }
    }

    return probe_host_memory_for_tree(tree);
}
