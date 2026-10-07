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
        const auto managed_python = managed_venv_python(managed_tools_dir, tool_mlx);
        const auto mlx_server = locate_binary(nullptr, {"mlx_lm.server"});
        const auto path_python = locate_binary(nullptr, {"python3", "python"});
        const bool mlx_via_managed = python_imports_mlx_lm(managed_python);
        const bool mlx_via_server = binary_ready(mlx_server);
        const bool mlx_via_python = python_imports_mlx_lm(path_python);
        const bool can_install =
            mlx_platform && (!path_python.isEmpty() || !QStandardPaths::findExecutable("python3").isEmpty() ||
                             !QStandardPaths::findExecutable("python").isEmpty());

        if (mlx_platform)
        {
            if (mlx_via_managed)
            {
                rows.push_back(make_result("mlx",
                                           "MLX (mlx_lm)",
                                           "ready",
                                           "Managed mlx-lm virtualenv ready",
                                           managed_python,
                                           {},
                                           false,
                                           mlx_selected,
                                           true));
            }
            else if (mlx_via_server)
            {
                const auto version = run_version_line(mlx_server, {"--help"});
                rows.push_back(make_result("mlx",
                                           "MLX (mlx_lm)",
                                           "ready",
                                           version.isEmpty() ? "mlx_lm.server found" : "mlx_lm.server available",
                                           mlx_server,
                                           {},
                                           false,
                                           mlx_selected,
                                           true));
            }
            else if (mlx_via_python)
            {
                rows.push_back(make_result("mlx",
                                           "MLX (mlx_lm)",
                                           "ready",
                                           "Python mlx-lm package available",
                                           path_python,
                                           {},
                                           false,
                                           mlx_selected,
                                           true));
            }
            else
            {
                rows.push_back(make_result("mlx",
                                           "MLX (mlx_lm)",
                                           "missing",
                                           can_install ? "Install mlx-lm into a managed virtualenv"
                                                       : "Python 3 is required to install mlx-lm",
                                           path_python,
                                           can_install ? "Install from Models → Backends"
                                                       : "Install Python 3, then use Models → Backends",
                                           false,
                                           mlx_selected,
                                           can_install));
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

    const auto llama = locate_llama_server(managed_tools_dir);
    const auto llama_cuda_managed =
        find_in_managed(managed_tools_dir,
                        QString::fromUtf8(tool_llama_server_cuda),
                        {QString::fromUtf8(tool_llama_server), "llama_server"});
    const bool using_cuda_build =
        !llama.isEmpty() && !llama_cuda_managed.isEmpty() &&
        (llama == llama_cuda_managed ||
         llama.contains(QStringLiteral("/%1/").arg(QString::fromUtf8(tool_llama_server_cuda))) ||
         llama.contains(QStringLiteral("\\%1\\").arg(QString::fromUtf8(tool_llama_server_cuda))));

    if (binary_ready(llama))
    {
        const auto version = run_version_line(llama);
        auto detail = version.isEmpty() ? std::string{"llama-server found"} : version.toStdString();
        if (using_cuda_build)
            detail += " (CUDA build)";
        rows.push_back(make_result("llamacpp",
                                   "llama.cpp (llama-server)",
                                   "ready",
                                   detail,
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
                                   "Install from Models → Setup, or set ELP_LLAMA_SERVER",
                                   !mlx_platform || !mlx_selected,
                                   llamacpp_selected,
                                   true));
    }

#ifndef Q_OS_MACOS
    if (!QStandardPaths::findExecutable("nvidia-smi").isEmpty())
    {
        const bool cuda_llama_ready = binary_ready(llama_cuda_managed);
        rows.push_back(make_result(
            backend_llamacpp_cuda,
            "llama.cpp (CUDA)",
            cuda_llama_ready ? "ready" : "missing",
            cuda_llama_ready ? "Managed CUDA llama-server ready"
                             : "GPU-enabled llama-server (required for --n-gpu-layers on NVIDIA)",
            cuda_llama_ready ? llama_cuda_managed : QString{},
            cuda_llama_ready ? std::string{}
                             : "Install from Models → Setup (downloads CUDA build + cudart)",
            false,
            selected_inference_id == "llamacpp-cuda" || using_cuda_build,
            true));

        rows.push_back(make_result("cuda",
                                   "NVIDIA CUDA",
                                   "ready",
                                   cuda_llama_ready
                                       ? "nvidia-smi detected; CUDA llama-server installed"
                                       : "nvidia-smi detected; install llama.cpp (CUDA) for GPU layers",
                                   QStandardPaths::findExecutable("nvidia-smi"),
                                   {},
                                   false,
                                   selected_inference_id == "llamacpp-cuda"));
    }
#endif

    const bool vllm_selected = selected_inference_id == "vllm";
#if defined(Q_OS_LINUX)
    const bool vllm_platform = !QStandardPaths::findExecutable("nvidia-smi").isEmpty();
#else
    const bool vllm_platform = false;
#endif
    {
        const auto managed_python = managed_venv_python(managed_tools_dir, tool_vllm);
        const auto vllm_cli = locate_binary(nullptr, {"vllm"});
        const auto path_python = locate_binary(nullptr, {"python3", "python"});
        auto python_imports_vllm = [&](const QString& py) {
            if (!binary_ready(py))
                return false;
            QProcess proc;
            proc.start(py, {"-c", "import vllm"});
            return proc.waitForFinished(8000) && proc.exitCode() == 0;
        };
        const bool vllm_via_managed = python_imports_vllm(managed_python);
        const bool can_install =
            vllm_platform && (!path_python.isEmpty() || !QStandardPaths::findExecutable("python3").isEmpty() ||
                              !QStandardPaths::findExecutable("python").isEmpty());

        if (!vllm_platform)
        {
            rows.push_back(make_result("vllm",
                                       "vLLM",
                                       "optional",
                                       "Linux with NVIDIA GPU only",
                                       {},
                                       {},
                                       false,
                                       false));
        }
        else if (vllm_via_managed)
        {
            rows.push_back(make_result("vllm",
                                       "vLLM",
                                       "ready",
                                       "Managed vllm virtualenv ready",
                                       managed_python,
                                       {},
                                       false,
                                       vllm_selected,
                                       true));
        }
        else if (binary_ready(vllm_cli))
        {
            rows.push_back(make_result("vllm",
                                       "vLLM",
                                       "ready",
                                       "vllm CLI found",
                                       vllm_cli,
                                       {},
                                       false,
                                       vllm_selected,
                                       true));
        }
        else if (python_imports_vllm(path_python))
        {
            rows.push_back(make_result("vllm",
                                       "vLLM",
                                       "ready",
                                       "Python vllm package available",
                                       path_python,
                                       {},
                                       false,
                                       vllm_selected,
                                       true));
        }
        else
        {
            rows.push_back(make_result("vllm",
                                       "vLLM",
                                       "missing",
                                       can_install ? "Install vLLM into a managed virtualenv"
                                                   : "Python 3 is required to install vLLM",
                                       {},
                                       can_install ? "Install from Models → Backends"
                                                   : "Install Python 3, then use Models → Backends",
                                       false,
                                       vllm_selected,
                                       can_install));
        }
    }

    rows.push_back(make_result("ollama",
                               "Ollama",
                               "optional",
                               "Not integrated with Electros LaunchPad yet",
                               QStandardPaths::findExecutable("ollama"),
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
