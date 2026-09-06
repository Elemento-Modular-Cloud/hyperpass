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

#include "backend_probe.h"

#include "binary_locator.h"
#include "managed_tools.h"

#include <multipass/constants.h>

#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>

namespace mp = multipass;

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

QString run_version_line(const QString& program, const QStringList& args = {})
{
    if (!binary_ready(program))
        return {};
    QProcess proc;
    proc.start(program, args.isEmpty() ? QStringList{"--version"} : args);
    if (!proc.waitForFinished(5000))
        return {};
    const auto out = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    const auto err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
    return out.isEmpty() ? err.split('\n').value(0).trimmed() : out.split('\n').value(0).trimmed();
}

mp::llm::BackendProbeResult make_result(std::string id,
                                        std::string name,
                                        std::string status,
                                        std::string detail,
                                        QString path,
                                        std::string install_hint,
                                        bool required,
                                        bool active,
                                        bool installable = false)
{
    mp::llm::BackendProbeResult row;
    row.id = std::move(id);
    row.name = std::move(name);
    row.status = std::move(status);
    row.detail = std::move(detail);
    row.binary_path = path.toStdString();
    row.install_hint = std::move(install_hint);
    row.required = required;
    row.active = active;
    row.installable = installable;
    return row;
}

bool inference_uses_llamacpp(const std::string& selected)
{
    return selected.rfind("llamacpp", 0) == 0;
}
} // namespace

std::vector<mp::llm::BackendProbeResult> mp::llm::probe_backends(const std::string& selected_inference_id,
                                                                 const QString& managed_tools_dir)
{
    std::vector<BackendProbeResult> rows;
    const bool mlx_enabled = mp::enable_mlx_backend;
    const bool mlx_selected = mlx_enabled && selected_inference_id == "mlx";
    const bool llamacpp_selected = inference_uses_llamacpp(selected_inference_id) ||
                                   (!mlx_enabled && selected_inference_id == "mlx");

    const auto llmfit = locate_binary(mp::llmfit_env_var,
                                      {"llmfit"},
                                      managed_tools_dir,
                                      QString::fromUtf8(tool_llmfit));
    if (binary_ready(llmfit))
    {
        const auto version = run_version_line(llmfit);
        rows.push_back(make_result("llmfit",
                                   "llmfit",
                                   "ready",
                                   version.isEmpty() ? "Catalog advisor available" : version.toStdString(),
                                   llmfit,
                                   {},
                                   true,
                                   false,
                                   true));
    }
    else
    {
        rows.push_back(make_result("llmfit",
                                   "llmfit",
                                   "missing",
                                   "Required for model catalog and fit scoring",
                                   {},
                                   "Install from Models → Backends, or set ELP_LLMFIT",
                                   true,
                                   false,
                                   true));
    }

#ifdef Q_OS_MACOS
    const bool mlx_platform = mlx_enabled;
#else
    const bool mlx_platform = false;
#endif

    if (mlx_enabled)
    {
        const auto mlx_server = locate_binary(nullptr, {"mlx_lm.server"});
        const auto python = locate_binary(nullptr, {"python3", "python"});
        const bool mlx_via_server = binary_ready(mlx_server);
        const bool mlx_via_python = python_imports_mlx_lm(python);

        if (mlx_platform)
        {
            if (mlx_via_server)
            {
                const auto version = run_version_line(mlx_server, {"--help"});
                rows.push_back(make_result("mlx",
                                           "MLX (mlx_lm)",
                                           "ready",
                                           version.isEmpty() ? "mlx_lm.server found" : "mlx_lm.server available",
                                           mlx_server,
                                           {},
                                           false,
                                           mlx_selected));
            }
            else if (mlx_via_python)
            {
                rows.push_back(make_result("mlx",
                                           "MLX (mlx_lm)",
                                           "ready",
                                           "Python mlx-lm package available",
                                           python,
                                           {},
                                           false,
                                           mlx_selected));
            }
            else if (!python.isEmpty())
            {
                rows.push_back(make_result("mlx",
                                           "MLX (mlx_lm)",
                                           "missing",
                                           "Python found but mlx-lm is not installed",
                                           python,
                                           "pip install mlx-lm",
                                           false,
                                           mlx_selected));
            }
            else
            {
                rows.push_back(make_result("mlx",
                                           "MLX (mlx_lm)",
                                           "missing",
                                           "Recommended inference backend on Apple Silicon",
                                           {},
                                           "pip install mlx-lm",
                                           false,
                                           mlx_selected));
            }
        }
        else
        {
            rows.push_back(make_result("mlx",
                                       "MLX (mlx_lm)",
                                       "optional",
                                       "Apple Silicon only; not used on this platform",
                                       {},
                                       {},
                                       false,
                                       false));
        }
    }

    const auto llama = locate_binary(mp::llama_server_env_var,
                                     {"llama-server", "llama_server"},
                                     managed_tools_dir,
                                     QString::fromUtf8(tool_llama_server));
    if (binary_ready(llama))
    {
        const auto version = run_version_line(llama);
        rows.push_back(make_result("llamacpp",
                                   "llama.cpp (llama-server)",
                                   "ready",
                                   version.isEmpty() ? "llama-server found" : version.toStdString(),
                                   llama,
                                   {},
                                   !mlx_platform || !mlx_selected,
                                   llamacpp_selected,
                                   true));
    }
    else
    {
        rows.push_back(make_result("llamacpp",
                                   "llama.cpp (llama-server)",
                                   "missing",
                                   mlx_selected ? "Fallback CPU/GPU inference backend"
                                                : "Primary inference backend on this platform",
                                   {},
                                   "Install from Models → Backends, or set ELP_LLAMA_SERVER",
                                   !mlx_platform || !mlx_selected,
                                   llamacpp_selected,
                                   true));
    }

#ifndef Q_OS_MACOS
    if (!QStandardPaths::findExecutable("nvidia-smi").isEmpty())
    {
        rows.push_back(make_result("cuda",
                                   "NVIDIA CUDA",
                                   "ready",
                                   "nvidia-smi detected; llama-server may use GPU layers",
                                   QStandardPaths::findExecutable("nvidia-smi"),
                                   {},
                                   false,
                                   selected_inference_id == "llamacpp-cuda"));
    }
#endif

    rows.push_back(make_result("ollama",
                               "Ollama",
                               "optional",
                               "Not integrated with Electros LaunchPad yet",
                               QStandardPaths::findExecutable("ollama"),
                               {},
                               false,
                               false));
    rows.push_back(make_result("vllm",
                               "vLLM",
                               "optional",
                               "Not integrated with Electros LaunchPad yet",
                               {},
                               {},
                               false,
                               false));
    rows.push_back(make_result("lmstudio",
                               "LM Studio",
                               "optional",
                               "Not integrated with Electros LaunchPad yet",
                               {},
                               {},
                               false,
                               false));

    return rows;
}
