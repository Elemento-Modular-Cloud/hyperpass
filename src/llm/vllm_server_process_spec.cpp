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

#include "vllm_server_process_spec.h"

#include <QDir>
#include <QSysInfo>

namespace mp = multipass;

namespace
{
bool is_aarch64_host()
{
    const auto arch = QSysInfo::currentCpuArchitecture().toLower();
    return arch.contains(QLatin1String("arm64")) || arch.contains(QLatin1String("aarch64"));
}
} // namespace

mp::VllmServerProcessSpec::VllmServerProcessSpec(VllmServerOptions options)
    : options_{std::move(options)}
{
    if (!options_.hf_cache_dir.isEmpty())
        QDir{}.mkpath(options_.hf_cache_dir);
}

QString mp::VllmServerProcessSpec::program() const
{
    return options_.program;
}

QStringList mp::VllmServerProcessSpec::arguments() const
{
    QStringList args;
    if (options_.launch_mode == QLatin1String("python"))
    {
        args << "-m" << "vllm.entrypoints.openai.api_server"
             << "--host" << "127.0.0.1"
             << "--port" << QString::number(options_.port)
             << "--model" << options_.model;
    }
    else
    {
        args << "serve" << options_.model
             << "--host" << "127.0.0.1"
             << "--port" << QString::number(options_.port);
    }

    if (!options_.openai_id.isEmpty())
        args << "--served-model-name" << options_.openai_id;
    if (!options_.dtype.isEmpty() && options_.dtype != QLatin1String("auto"))
        args << "--dtype" << options_.dtype;
    if (options_.gpu_memory_utilization > 0.0)
        args << "--gpu-memory-utilization"
             << QString::number(options_.gpu_memory_utilization, 'f', 2);
    if (options_.max_model_len > 0)
        args << "--max-model-len" << QString::number(options_.max_model_len);
    // CUDA graphs / compile paths are still flaky on GB10-class aarch64; eager
    // mode avoids EngineCore dying during AsyncMPClient startup.
    if (is_aarch64_host())
        args << "--enforce-eager";

    return args;
}

QString mp::VllmServerProcessSpec::apparmor_profile() const
{
    return QString();
}

QProcessEnvironment mp::VllmServerProcessSpec::environment() const
{
    auto env = ProcessSpec::environment();
    if (!options_.hf_cache_dir.isEmpty())
    {
        env.insert("HF_HUB_CACHE", options_.hf_cache_dir);
        env.insert("HUGGINGFACE_HUB_CACHE", options_.hf_cache_dir);
    }
    if (!options_.hf_token.isEmpty())
        env.insert("HF_TOKEN", options_.hf_token);
    // CUDA was often already touched in the parent; force spawn for EngineCore.
    env.insert("VLLM_WORKER_MULTIPROC_METHOD", "spawn");
    // otel wrappers clutter failure toasts and are unused in LaunchPad.
    env.insert("OTEL_SDK_DISABLED", "true");
    env.insert("VLLM_NO_USAGE_STATS", "1");
    return env;
}

QString mp::VllmServerProcessSpec::identifier() const
{
    return QStringLiteral("vllm-%1").arg(options_.port);
}
