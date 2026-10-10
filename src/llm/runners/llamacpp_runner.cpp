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

#include "llamacpp_runner.h"

#include "../binary_locator.h"
#include "../llama_server_process_spec.h"
#include "../llm_memory_claim.h"
#include "../managed_tools.h"

#include <multipass/constants.h>
#include <multipass/platform.h>

#include <QFileInfo>

#include <stdexcept>

namespace mp = multipass;
namespace llm = multipass::llm;

std::string llm::LlamaCppRunner::id() const
{
    return runner_llamacpp;
}

std::string llm::LlamaCppRunner::display_name() const
{
    return "llama.cpp (llama-server)";
}

std::vector<std::string> llm::LlamaCppRunner::formats() const
{
    return {format_gguf};
}

bool llm::LlamaCppRunner::available_on_platform() const
{
    return true;
}

bool llm::LlamaCppRunner::uses_gpu(RunnerDevice device) const
{
    return device == RunnerDevice::metal || device == RunnerDevice::cuda;
}

std::string llm::LlamaCppRunner::session_backend_name(RunnerDevice device) const
{
    switch (device)
    {
    case RunnerDevice::cuda:
        return "llamacpp-cuda";
    case RunnerDevice::metal:
        return "llamacpp-metal";
    case RunnerDevice::cpu:
    default:
        return runner_llamacpp;
    }
}

long long llm::LlamaCppRunner::estimate_claim_bytes(const RunnerLaunchContext& ctx) const
{
    const auto parallel = ctx.resolved.llama.parallel > 0 ? ctx.resolved.llama.parallel : 1;
    return estimate_llama_claim_bytes(ctx.artifact.size_bytes,
                                      ctx.resolved.ctx_size,
                                      parallel,
                                      ctx.resolved.llama.cache_type_k.toStdString(),
                                      ctx.resolved.llama.cache_type_v.toStdString(),
                                      ctx.artifact.path);
}

std::unique_ptr<mp::Process> llm::LlamaCppRunner::start(const RunnerLaunchContext& ctx) const
{
    const auto tools_root = managed_tools_root(ctx.data_directory);
    const auto llama = locate_llama_server(tools_root);
    if (llama.isEmpty())
        throw std::runtime_error(
            "llama-server is not installed. Use Models → Setup to install "
            "llama.cpp (CUDA on NVIDIA hosts) or set ELP_LLAMA_SERVER.");

    QString library_dir;
    if (is_under_managed_tools(llama, tools_root))
        library_dir = QFileInfo{llama}.absolutePath();

    LlamaServerOptions options;
    apply_resolved_to_options(options, ctx.resolved);
    options.program = llama;
    options.model_path = QString::fromStdString(ctx.artifact.path);
    options.openai_id = QString::fromStdString(ctx.openai_id);
    options.port = ctx.port;
    options.library_dir = library_dir;
    options.mmproj_path = QString::fromStdString(ctx.artifact.mmproj_path);
    return platform::make_process(std::make_unique<LlamaServerProcessSpec>(std::move(options)));
}
