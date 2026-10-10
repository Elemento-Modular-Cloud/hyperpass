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

#include "vllm_memory_budget.h"

#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSysInfo>

#include <algorithm>
#include <cmath>

namespace mp = multipass;

namespace
{
long long host_total_ram_bytes()
{
    QFile meminfo{QStringLiteral("/proc/meminfo")};
    if (!meminfo.open(QIODevice::ReadOnly | QIODevice::Text))
        return 0;
    const auto text = QString::fromUtf8(meminfo.readAll());
    // MemTotal:       123456789 kB
    static const QRegularExpression re{QStringLiteral(R"(MemTotal:\s*(\d+)\s*kB)")};
    const auto match = re.match(text);
    if (!match.hasMatch())
        return 0;
    bool ok = false;
    const auto kib = match.captured(1).toLongLong(&ok);
    if (!ok || kib <= 0)
        return 0;
    return kib * 1024LL;
}

long long nvidia_smi_total_bytes()
{
    if (QStandardPaths::findExecutable(QStringLiteral("nvidia-smi")).isEmpty())
        return 0;

    QProcess proc;
    proc.start(QStringLiteral("nvidia-smi"),
               {QStringLiteral("--query-gpu=memory.total"),
                QStringLiteral("--format=csv,noheader,nounits")});
    if (!proc.waitForFinished(3000) || proc.exitCode() != 0)
        return 0;

    const auto line = QString::fromUtf8(proc.readAllStandardOutput()).trimmed().split('\n').value(0).trimmed();
    if (line.isEmpty() || line.contains(QLatin1String("N/A"), Qt::CaseInsensitive))
        return 0;

    bool ok = false;
    const auto mib = line.toLongLong(&ok);
    if (!ok || mib <= 0)
        return 0;
    return mib * 1024LL * 1024LL;
}
} // namespace

double mp::vllm_host_util_cap()
{
    const auto arch = QSysInfo::currentCpuArchitecture().toLower();
    if (arch.contains(QLatin1String("arm64")) || arch.contains(QLatin1String("aarch64")))
        return 0.80;
    return 0.90;
}

long long mp::vllm_kv_budget_bytes(int max_model_len)
{
    // Same rough scale as LlmService::estimate_claim at f16: ~0.25 MiB per token.
    const auto ctx = std::max(max_model_len, 2048);
    return static_cast<long long>(static_cast<double>(ctx) * 2.0 * 1024.0 * 1024.0 / 8.0);
}

long long mp::vllm_budget_bytes(long long size_bytes, int max_model_len)
{
    const auto weights = std::max(0LL, size_bytes);
    return weights + vllm_kv_budget_bytes(max_model_len) + vllm_runtime_overhead_bytes;
}

double mp::estimate_vllm_gpu_memory_utilization(long long size_bytes,
                                                int max_model_len,
                                                long long gpu_total_bytes,
                                                double host_cap)
{
    const auto cap = host_cap > 0.0 ? host_cap : vllm_host_util_cap();
    if (gpu_total_bytes <= 0)
        return cap;

    const auto budget = static_cast<double>(vllm_budget_bytes(size_bytes, max_model_len));
    const auto raw = budget / static_cast<double>(gpu_total_bytes);
    const auto clamped = std::clamp(raw, vllm_util_floor, cap);
    // Two decimal places match --gpu-memory-utilization formatting in the process spec.
    return std::round(clamped * 100.0) / 100.0;
}

long long mp::vllm_claim_bytes(double gpu_memory_utilization,
                               long long gpu_total_bytes,
                               long long size_bytes,
                               int max_model_len)
{
    if (gpu_total_bytes > 0 && gpu_memory_utilization > 0.0)
    {
        const auto util = std::clamp(gpu_memory_utilization, vllm_util_floor, 1.0);
        return static_cast<long long>(util * static_cast<double>(gpu_total_bytes));
    }
    return vllm_budget_bytes(size_bytes, max_model_len);
}

long long mp::probe_gpu_total_bytes()
{
    if (const auto from_smi = nvidia_smi_total_bytes(); from_smi > 0)
        return from_smi;
    return host_total_ram_bytes();
}
