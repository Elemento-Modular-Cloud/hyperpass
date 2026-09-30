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

#include "runner_registry.h"

#include "llamacpp_runner.h"
#include "mlx_runner.h"
#include "vllm_runner.h"

#include <multipass/constants.h>
#include <multipass/settings/settings.h>

#include <QStandardPaths>
#include <QString>

namespace mp = multipass;
namespace llm = multipass::llm;

#ifndef Q_OS_MACOS
namespace
{
bool cuda_present()
{
    return !QStandardPaths::findExecutable("nvidia-smi").isEmpty();
}
} // namespace
#endif

llm::RunnerRegistry::RunnerRegistry()
{
    owners.push_back(std::make_unique<LlamaCppRunner>());
    owners.push_back(std::make_unique<MlxRunner>());
    owners.push_back(std::make_unique<VllmRunner>());
    for (const auto& r : owners)
        ordered.push_back(r.get());
}

const llm::InferenceRunner* llm::RunnerRegistry::get(const std::string& runner_id) const
{
    for (const auto* r : ordered)
    {
        if (r->id() == runner_id)
            return r;
    }
    return nullptr;
}

llm::RunnerDevice llm::RunnerRegistry::llama_device_for_platform() const
{
#ifdef Q_OS_MACOS
    return RunnerDevice::metal;
#else
    return cuda_present() ? RunnerDevice::cuda : RunnerDevice::cpu;
#endif
}

llm::ResolvedRunner llm::RunnerRegistry::with_device(const InferenceRunner* runner) const
{
    ResolvedRunner out;
    out.runner = runner;
    if (!runner)
        return out;
    if (runner->id() == runner_llamacpp)
        out.device = llama_device_for_platform();
    else if (runner->id() == runner_vllm)
        out.device = RunnerDevice::cuda;
    else
        out.device = RunnerDevice::metal;
    return out;
}

llm::ResolvedRunner llm::RunnerRegistry::select_default() const
{
    QString setting = "auto";
    try
    {
        setting = MP_SETTINGS.get(mp::llm_backend_key).toLower();
    }
    catch (const std::exception&)
    {
    }

    if (setting == "mlx")
    {
        if (const auto* mlx = get(runner_mlx); mlx && mlx->available_on_platform())
            return with_device(mlx);
    }
    if (setting == "vllm")
    {
        if (const auto* vllm = get(runner_vllm); vllm && vllm->available_on_platform())
            return with_device(vllm);
    }
    if (setting == "cuda")
    {
        auto resolved = with_device(get(runner_llamacpp));
        resolved.device = RunnerDevice::cuda;
        return resolved;
    }
    if (setting == "llamacpp")
        return with_device(get(runner_llamacpp));

    // auto → platform llama (never auto-pick vLLM)
    return with_device(get(runner_llamacpp));
}

llm::ResolvedRunner llm::RunnerRegistry::resolve(const std::string& runtime_request) const
{
    const auto runtime = QString::fromStdString(runtime_request).trimmed().toLower();
    if (runtime == "mlx")
    {
        if (const auto* mlx = get(runner_mlx); mlx && mlx->available_on_platform())
            return with_device(mlx);
    }
    if (runtime == "vllm")
    {
        if (const auto* vllm = get(runner_vllm); vllm && vllm->available_on_platform())
            return with_device(vllm);
        // Explicit request on unsupported host: still resolve to the runner so load fails clearly.
        if (const auto* vllm = get(runner_vllm))
            return with_device(vllm);
    }
    if (runtime == "llamacpp" || runtime == "llama.cpp")
        return with_device(get(runner_llamacpp));
    if (runtime.startsWith("llamacpp"))
        return with_device(get(runner_llamacpp));

    return select_default();
}
