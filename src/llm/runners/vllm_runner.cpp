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

#include "vllm_runner.h"

#include "../binary_locator.h"
#include "../managed_tools.h"
#include "../vllm_server_process_spec.h"

#include <multipass/platform.h>

#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>

#include <stdexcept>

namespace mp = multipass;
namespace llm = multipass::llm;

namespace
{
bool binary_ready(const QString& path)
{
    if (path.isEmpty())
        return false;
    const QFileInfo info{path};
    return info.exists() && info.isExecutable();
}

bool python_imports_vllm(const QString& python)
{
    if (!binary_ready(python))
        return false;
    QProcess proc;
    proc.start(python, {"-c", "import vllm"});
    return proc.waitForFinished(8000) && proc.exitCode() == 0;
}

std::pair<QString, QString> resolve_vllm_launch(const mp::Path& data_directory)
{
    const auto tools_root = llm::managed_tools_root(data_directory);
    const auto managed_python = llm::managed_venv_python(tools_root, llm::tool_vllm);
    if (python_imports_vllm(managed_python))
        return {managed_python, QStringLiteral("python")};

    auto program = llm::locate_binary(nullptr, {"vllm"});
    if (!program.isEmpty())
        return {program, QStringLiteral("cli")};

    const auto python = llm::locate_binary(nullptr, {"python3", "python"});
    if (python_imports_vllm(python))
        return {python, QStringLiteral("python")};

    return {};
}
} // namespace

std::string llm::VllmRunner::id() const
{
    return runner_vllm;
}

std::string llm::VllmRunner::display_name() const
{
    return "vLLM";
}

std::vector<std::string> llm::VllmRunner::formats() const
{
    return {format_hf};
}

bool llm::VllmRunner::available_on_platform() const
{
#if defined(Q_OS_LINUX)
    return !QStandardPaths::findExecutable("nvidia-smi").isEmpty();
#else
    return false;
#endif
}

bool llm::VllmRunner::uses_gpu(RunnerDevice) const
{
    return true;
}

std::string llm::VllmRunner::session_backend_name(RunnerDevice) const
{
    return runner_vllm;
}

std::unique_ptr<mp::Process> llm::VllmRunner::start(const RunnerLaunchContext& ctx) const
{
    if (!available_on_platform())
        throw std::runtime_error("vLLM requires Linux with an NVIDIA GPU");

    const auto [program, mode] = resolve_vllm_launch(ctx.data_directory);
    if (program.isEmpty())
        throw std::runtime_error(
            "vLLM is not installed. Use Models → Backends → Install, or: pip install vllm");

    VllmServerOptions options;
    options.program = program;
    options.launch_mode = mode;
    options.model = QString::fromStdString(ctx.artifact.path);
    options.port = ctx.port;
    options.openai_id = QString::fromStdString(ctx.openai_id);
    options.hf_cache_dir = QDir{ctx.data_directory}.filePath(QStringLiteral("llm/hf-cache"));
    options.hf_token = QString::fromStdString(ctx.hf_token);

    const auto& p = ctx.resolved.echoed;
    if (!p.dtype().empty())
        options.dtype = QString::fromStdString(p.dtype());
    if (p.has_gpu_memory_utilization() && p.gpu_memory_utilization() > 0)
        options.gpu_memory_utilization = p.gpu_memory_utilization();
    if (p.has_max_model_len() && p.max_model_len() > 0)
        options.max_model_len = p.max_model_len();
    else if (ctx.resolved.ctx_size > 0)
        options.max_model_len = ctx.resolved.ctx_size;

    return platform::make_process(std::make_unique<VllmServerProcessSpec>(std::move(options)));
}
