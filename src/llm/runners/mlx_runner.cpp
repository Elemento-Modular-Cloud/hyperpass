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

#include "mlx_runner.h"

#include "../binary_locator.h"
#include "../llm_memory_claim.h"
#include "../managed_tools.h"
#include "../mlx_server_process_spec.h"

#include <multipass/constants.h>
#include <multipass/platform.h>

#include <QDir>
#include <QFileInfo>
#include <QProcess>

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

bool python_imports_mlx_lm(const QString& python)
{
    if (!binary_ready(python))
        return false;
    QProcess proc;
    proc.start(python, {"-c", "import mlx_lm"});
    return proc.waitForFinished(5000) && proc.exitCode() == 0;
}

QString resolve_mlx_program(const mp::Path& data_directory)
{
    const auto tools_root = llm::managed_tools_root(data_directory);
    const auto managed_python = llm::managed_venv_python(tools_root, llm::tool_mlx);
    if (python_imports_mlx_lm(managed_python))
        return managed_python;

    auto mlx = llm::locate_binary(nullptr, {"mlx_lm.server"});
    if (!mlx.isEmpty())
        return mlx;

    const auto python = llm::locate_binary(nullptr, {"python3", "python"});
    if (python_imports_mlx_lm(python))
        return python;
    return {};
}
} // namespace

std::string llm::MlxRunner::id() const
{
    return runner_mlx;
}

std::string llm::MlxRunner::display_name() const
{
    return "MLX (mlx_lm)";
}

std::vector<std::string> llm::MlxRunner::formats() const
{
    return {format_mlx};
}

bool llm::MlxRunner::available_on_platform() const
{
#ifdef Q_OS_MACOS
    return mp::enable_mlx_backend;
#else
    return false;
#endif
}

bool llm::MlxRunner::uses_gpu(RunnerDevice) const
{
    return true;
}

std::string llm::MlxRunner::session_backend_name(RunnerDevice) const
{
    return runner_mlx;
}

long long llm::MlxRunner::estimate_claim_bytes(const RunnerLaunchContext& ctx) const
{
    return estimate_mlx_claim_bytes(ctx.artifact.size_bytes);
}

std::unique_ptr<mp::Process> llm::MlxRunner::start(const RunnerLaunchContext& ctx) const
{
    if (!available_on_platform())
        throw std::runtime_error("MLX is not available on this platform");

    const auto mlx = resolve_mlx_program(ctx.data_directory);
    if (mlx.isEmpty())
        throw std::runtime_error(
            "mlx-lm is not installed. Use Models → Backends → Install, or: pip install mlx-lm");

    MlxServerOptions options;
    options.program = mlx;
    options.model_path = QString::fromStdString(ctx.artifact.path);
    options.port = ctx.port;
    options.hf_cache_dir = QDir{ctx.data_directory}.filePath(QStringLiteral("llm/hf-cache"));
    options.hf_token = QString::fromStdString(ctx.hf_token);

    return platform::make_process(std::make_unique<MlxServerProcessSpec>(std::move(options)));
}
