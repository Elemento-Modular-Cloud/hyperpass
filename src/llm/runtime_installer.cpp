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

#include "runtime_installer.h"

#include "managed_tools.h"

#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/logging/log.h>

#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTemporaryDir>
#include <QUrl>

#include <algorithm>
#include <chrono>
#include <stdexcept>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "llm-installer";

QString host_cpu_arch()
{
    const auto arch = QSysInfo::currentCpuArchitecture().toLower();
    if (arch == "arm64" || arch == "aarch64")
        return "arm64";
    if (arch == "x86_64" || arch == "amd64" || arch == "x64")
        return "x64";
    return arch;
}

QString llmfit_triple()
{
    const auto arch = host_cpu_arch();
#ifdef Q_OS_MACOS
    return arch == "arm64" ? "aarch64-apple-darwin" : "x86_64-apple-darwin";
#elif defined(Q_OS_WIN)
    return arch == "arm64" ? "aarch64-pc-windows-msvc" : "x86_64-pc-windows-msvc";
#else
    return arch == "arm64" ? "aarch64-unknown-linux-gnu" : "x86_64-unknown-linux-gnu";
#endif
}

QString llama_platform_token()
{
    const auto arch = host_cpu_arch();
#ifdef Q_OS_MACOS
    return arch == "arm64" ? "macos-arm64" : "macos-x64";
#elif defined(Q_OS_WIN)
    return arch == "arm64" ? "win-cpu-arm64" : "win-cpu-x64";
#else
    return arch == "arm64" ? "ubuntu-arm64" : "ubuntu-x64";
#endif
}

// Official ggml CUDA Ubuntu tokens for pinned_llama_cuda_build (CUDA 13.3).
QString llama_cuda_platform_token()
{
#if defined(Q_OS_LINUX)
    return host_cpu_arch() == "arm64" ? "ubuntu-cuda-13.3-arm64" : "ubuntu-cuda-13.3-x64";
#else
    throw std::runtime_error(
        "llama.cpp CUDA managed install is only available on Linux with NVIDIA GPU");
#endif
}

bool archive_is_zip(const QString& name)
{
    return name.endsWith(".zip", Qt::CaseInsensitive);
}

QString file_sha256_hex(const QString& path)
{
    QFile file{path};
    if (!file.open(QIODevice::ReadOnly))
        throw std::runtime_error(fmt::format("unable to open '{}' for checksum", path.toStdString()));

    QCryptographicHash hash{QCryptographicHash::Sha256};
    if (!hash.addData(&file))
        throw std::runtime_error(fmt::format("unable to hash '{}'", path.toStdString()));
    return QString::fromUtf8(hash.result().toHex());
}

QString parse_sha256_sidecar(const QByteArray& payload)
{
    // Formats: "<hex>  <filename>" or bare hex.
    const auto line = QString::fromUtf8(payload).trimmed().split('\n').value(0).trimmed();
    const auto hex = line.split(QRegularExpression("\\s+")).value(0).trimmed().toLower();
    if (hex.size() != 64)
        throw std::runtime_error("invalid sha256 sidecar contents");
    return hex;
}

void ensure_executable(const QString& path)
{
#ifndef Q_OS_WIN
    QFile file{path};
    auto perms = file.permissions();
    file.setPermissions(perms | QFileDevice::ExeOwner | QFileDevice::ExeUser | QFileDevice::ExeGroup |
                        QFileDevice::ExeOther);
#else
    Q_UNUSED(path);
#endif
}

void remove_path_recursively(const QString& path)
{
    QDir dir{path};
    if (dir.exists())
        dir.removeRecursively();
    else
        QFile::remove(path);
}

bool copy_tree(const QString& src, const QString& dst)
{
    QDir src_dir{src};
    if (!src_dir.exists())
        return false;
    QDir{}.mkpath(dst);
    const auto entries = src_dir.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden);
    for (const auto& entry : entries)
    {
        const auto target = QDir{dst}.filePath(entry.fileName());
        if (entry.isDir())
        {
            if (!copy_tree(entry.absoluteFilePath(), target))
                return false;
        }
        else
        {
            QFile::remove(target);
            if (!QFile::copy(entry.absoluteFilePath(), target))
                return false;
        }
    }
    return true;
}

QString find_binary_under(const QDir& dir, const QStringList& names)
{
    for (const auto& name : names)
    {
        const QFileInfo direct{dir.filePath(name)};
        if (direct.exists() && direct.isFile())
            return direct.absoluteFilePath();
#ifdef Q_OS_WIN
        const QFileInfo exe{dir.filePath(name + ".exe")};
        if (exe.exists() && exe.isFile())
            return exe.absoluteFilePath();
#endif
    }
    for (const auto& entry : dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot))
    {
        const auto nested = find_binary_under(QDir{entry.absoluteFilePath()}, names);
        if (!nested.isEmpty())
            return nested;
    }
    return {};
}

// Pinned llama.cpp archive digests for b10819 (from GitHub release asset digests).
QString llama_sha256_for(const QString& platform_token)
{
    static const std::unordered_map<std::string, QString> digests{
        {"macos-arm64", "8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66"},
        {"macos-x64", "04dd13ec03120685bd6e1931e8f1562d2c981ca076a3e63cc44e9a199b37816a"},
        {"ubuntu-arm64", "6f6f7e1e9b371d4840860a79ccbf4ad6f7da9da76349ce73079e3289b01033ec"},
        {"ubuntu-x64", "bff96585dfa126d2bc915367b3735982a5e67ddf887138a7c6e9d7cc9b438146"},
        {"win-cpu-arm64", "5802d55f633b68bf6dbe574d75f9f47387761fe3b6ddef4193ea9ea423642afb"},
        {"win-cpu-x64", "4599e502b374196d24600ea9b03c842a448c853116a15b55e8ba502bdc727b3f"},
    };
    const auto it = digests.find(platform_token.toStdString());
    if (it == digests.end())
        throw std::runtime_error(fmt::format("no pinned sha256 for llama.cpp platform '{}'",
                                             platform_token.toStdString()));
    return it->second;
}

// Pinned digests for b11062 CUDA (+ cudart) Ubuntu assets.
QString llama_cuda_sha256_for(const QString& platform_token)
{
    static const std::unordered_map<std::string, QString> digests{
        {"ubuntu-cuda-13.3-arm64", "6acf8c0ed26e3798d7a1d0d16dbbd7f029a351d625680f83afc21b51e39dccd1"},
        {"ubuntu-cuda-13.3-x64", "a8edcf92dce7577a891473c95b1f3a9f1dbf9a77e092e07d9e80f24efe9553c1"},
        {"cudart-ubuntu-cuda-13.3-arm64",
         "6d581e3bb5d1e70ea5dca4e41bd6f65483a3f61c1fd27ae49568f8cfd381b4a3"},
        {"cudart-ubuntu-cuda-13.3-x64",
         "97225747b60f12607d5cfd4b1219d8146c2184a790fa8b08b69e01347816c4b8"},
    };
    const auto it = digests.find(platform_token.toStdString());
    if (it == digests.end())
        throw std::runtime_error(fmt::format("no pinned sha256 for llama.cpp CUDA platform '{}'",
                                             platform_token.toStdString()));
    return it->second;
}

void copy_shared_libs_into(const QString& src_root, const QString& dest_dir)
{
    QDir{}.mkpath(dest_dir);
    QDirIterator it{src_root,
                    QDir::Files,
                    QDirIterator::Subdirectories};
    while (it.hasNext())
    {
        it.next();
        const auto name = it.fileName();
        if (!(name.contains(".so") || name.endsWith(".dylib", Qt::CaseInsensitive) ||
              name.endsWith(".dll", Qt::CaseInsensitive)))
            continue;
        const auto target = QDir{dest_dir}.filePath(name);
        QFile::remove(target);
        if (!QFile::copy(it.filePath(), target))
            throw std::runtime_error(
                fmt::format("failed to install companion library '{}'", name.toStdString()));
    }
}
} // namespace

QString mp::llm::backend_id_to_tool_name(const QString& backend_id)
{
    if (backend_id == "llmfit")
        return QString::fromUtf8(tool_llmfit);
    if (backend_id == "llamacpp")
        return QString::fromUtf8(tool_llama_server);
    if (backend_id == backend_llamacpp_cuda)
        return QString::fromUtf8(tool_llama_server_cuda);
    if (backend_id == tool_mlx)
        return QString::fromUtf8(tool_mlx);
    if (backend_id == tool_vllm)
        return QString::fromUtf8(tool_vllm);
    return {};
}

mp::llm::RuntimeAsset mp::llm::resolve_runtime_asset(const QString& backend_id)
{
    if (is_pip_backend(backend_id))
        throw std::runtime_error(fmt::format(
            "backend '{}' is installed via pip into a managed venv, not an archive asset",
            backend_id.toStdString()));

    const auto tool = backend_id_to_tool_name(backend_id);
    if (tool.isEmpty())
        throw std::runtime_error(
            fmt::format("unknown backend id '{}'; expected llmfit, llamacpp, llamacpp-cuda, mlx, or vllm",
                        backend_id.toStdString()));

    RuntimeAsset asset;
    asset.tool_name = tool;

    if (tool == tool_llmfit)
    {
        const auto triple = llmfit_triple();
        const auto version = QString::fromUtf8(pinned_llmfit_version);
        const auto ext =
#ifdef Q_OS_WIN
            QStringLiteral(".zip");
#else
            QStringLiteral(".tar.gz");
#endif
        asset.version = version;
        asset.archive_name = QStringLiteral("llmfit-%1-%2%3").arg(version, triple, ext);
        asset.url = QStringLiteral("https://github.com/AlexsJones/llmfit/releases/download/%1/%2")
                        .arg(version, asset.archive_name);
        asset.sha256_from_sidecar = true;
        return asset;
    }

    if (tool == tool_llama_server_cuda)
    {
#if !defined(Q_OS_LINUX)
        throw std::runtime_error(
            "llama.cpp CUDA managed install is only available on Linux with NVIDIA GPU");
#else
        const auto build = QString::fromUtf8(pinned_llama_cuda_build);
        const auto platform = llama_cuda_platform_token();
        asset.version = build;
        asset.archive_name = QStringLiteral("llama-%1-bin-%2.tar.gz").arg(build, platform);
        asset.url = QStringLiteral("https://github.com/ggml-org/llama.cpp/releases/download/%1/%2")
                        .arg(build, asset.archive_name);
        asset.sha256_hex = llama_cuda_sha256_for(platform);
        asset.sha256_from_sidecar = false;
        asset.companion_archive_name =
            QStringLiteral("cudart-llama-%1-bin-%2.tar.gz").arg(build, platform);
        asset.companion_url =
            QStringLiteral("https://github.com/ggml-org/llama.cpp/releases/download/%1/%2")
                .arg(build, asset.companion_archive_name);
        asset.companion_sha256_hex =
            llama_cuda_sha256_for(QStringLiteral("cudart-%1").arg(platform));
        return asset;
#endif
    }

    const auto build = QString::fromUtf8(pinned_llama_build);
    const auto platform = llama_platform_token();
    const auto real_ext = platform.startsWith("win") ? QStringLiteral(".zip") : QStringLiteral(".tar.gz");
    asset.version = build;
    asset.archive_name = QStringLiteral("llama-%1-bin-%2%3").arg(build, platform, real_ext);
    asset.url = QStringLiteral("https://github.com/ggml-org/llama.cpp/releases/download/%1/%2")
                    .arg(build, asset.archive_name);
    asset.sha256_hex = llama_sha256_for(platform);
    asset.sha256_from_sidecar = false;
    return asset;
}

mp::llm::RuntimeInstaller::RuntimeInstaller(URLDownloader& downloader, Path data_directory)
    : downloader{downloader}, data_directory{std::move(data_directory)}
{
}

namespace
{
bool python_imports_module(const QString& python, const QString& module)
{
    if (python.isEmpty() || module.isEmpty())
        return false;
    const QFileInfo info{python};
    if (!info.exists() || !info.isExecutable())
        return false;
    QProcess proc;
    proc.start(python, {"-c", QStringLiteral("import %1").arg(module)});
    return proc.waitForFinished(15000) && proc.exitCode() == 0;
}

QString host_python()
{
    return QStandardPaths::findExecutable("python3").isEmpty()
               ? QStandardPaths::findExecutable("python")
               : QStandardPaths::findExecutable("python3");
}

using LineCallback = std::function<void(std::string_view line)>;

void emit_complete_lines(std::string& carry,
                         const QByteArray& chunk,
                         const LineCallback& on_line,
                         bool flush)
{
    if (!on_line)
        return;
    for (const auto& line :
         mp::llm::split_install_log_chunk(carry, std::string_view{chunk.constData(), static_cast<size_t>(chunk.size())}, flush))
    {
        if (!line.empty())
            on_line(line);
    }
}

void run_python(const QString& python,
                const QStringList& args,
                const std::string& what,
                int timeout_ms = 600000,
                const LineCallback& on_line = {})
{
    QProcess proc;
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start(python, args);
    if (!proc.waitForStarted(15000))
        throw std::runtime_error(fmt::format("failed to start {}: {}", what, python.toStdString()));

    std::string carry;
    std::string captured;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds{timeout_ms};
    while (proc.state() != QProcess::NotRunning)
    {
        if (std::chrono::steady_clock::now() > deadline)
        {
            proc.kill();
            proc.waitForFinished(5000);
            throw std::runtime_error(fmt::format("{} timed out after {}ms", what, timeout_ms));
        }
        if (proc.waitForReadyRead(200))
        {
            const auto chunk = proc.readAll();
            captured.append(chunk.constData(), static_cast<size_t>(chunk.size()));
            if (captured.size() > 256 * 1024)
                captured.erase(0, captured.size() - 128 * 1024);
            emit_complete_lines(carry, chunk, on_line, false);
        }
    }
    const auto rest = proc.readAll();
    if (!rest.isEmpty())
    {
        captured.append(rest.constData(), static_cast<size_t>(rest.size()));
        emit_complete_lines(carry, rest, on_line, false);
    }
    emit_complete_lines(carry, {}, on_line, true);

    if (proc.exitCode() != 0)
    {
        auto detail = QString::fromStdString(captured).trimmed().toStdString();
        if (detail.empty())
            detail = fmt::format("exit code {}", proc.exitCode());
        throw std::runtime_error(fmt::format("{} failed: {}", what, detail));
    }
}

void ensure_pip_backend_supported(const QString& backend_id)
{
    if (backend_id == mp::llm::tool_mlx)
    {
#ifndef Q_OS_MACOS
        throw std::runtime_error("MLX can only be installed on macOS");
#endif
        if (!mp::enable_mlx_backend)
            throw std::runtime_error("MLX backend is disabled in this build");
        return;
    }
    if (backend_id == mp::llm::tool_vllm)
    {
#ifndef Q_OS_LINUX
        throw std::runtime_error("vLLM can only be installed on Linux");
#else
        return;
#endif
    }
    throw std::runtime_error(fmt::format("not a pip-installable backend '{}'", backend_id.toStdString()));
}
} // namespace

std::vector<std::string> mp::llm::split_install_log_chunk(std::string& carry,
                                                          std::string_view chunk,
                                                          bool flush)
{
    carry.append(chunk);
    std::vector<std::string> lines;
    std::string::size_type start = 0;
    while (true)
    {
        const auto pos = carry.find('\n', start);
        if (pos == std::string::npos)
            break;
        auto line = carry.substr(start, pos - start);
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        lines.push_back(std::move(line));
        start = pos + 1;
    }
    if (start > 0)
        carry.erase(0, start);
    if (flush && !carry.empty())
    {
        if (!carry.empty() && carry.back() == '\r')
            carry.pop_back();
        lines.push_back(std::move(carry));
        carry.clear();
    }
    return lines;
}

QString mp::llm::RuntimeInstaller::install(const QString& backend_id,
                                           const InstallProgressCallback& on_progress)
{
    if (is_pip_backend(backend_id))
        return install_pip_backend(backend_id, on_progress);

    if (backend_id == backend_llamacpp_cuda &&
        QStandardPaths::findExecutable("nvidia-smi").isEmpty())
    {
        throw std::runtime_error(
            "llama.cpp CUDA install requires NVIDIA drivers (nvidia-smi not found)");
    }

    const auto asset = resolve_runtime_asset(backend_id);
    const auto names = asset.tool_name == tool_llmfit
                           ? QStringList{QString::fromUtf8(tool_llmfit)}
                           : QStringList{QString::fromUtf8(tool_llama_server), "llama_server"};
    const auto tools_root = managed_tools_root(data_directory);
    const auto existing = find_in_managed(tools_root, asset.tool_name, names);
    if (!existing.isEmpty())
    {
        if (on_progress)
            on_progress(InstallProgress{"ready", 100, existing, "already installed", {}});
        return existing;
    }
    return install_asset(asset, on_progress);
}

QString mp::llm::RuntimeInstaller::install_pip_backend(const QString& backend_id,
                                                       const InstallProgressCallback& on_progress)
{
    ensure_pip_backend_supported(backend_id);

    auto emit_progress = [&](const char* status, int percent, const QString& path = {},
                             const std::string& message = {}, const std::string& log_line = {}) {
        if (on_progress)
            on_progress(InstallProgress{status, percent, path, message, log_line});
    };

    const auto package = pip_package_for_backend(backend_id);
    const auto import_name = backend_id == tool_mlx ? QStringLiteral("mlx_lm") : backend_id;
    const auto tools_root = managed_tools_root(data_directory);
    QDir{}.mkpath(tools_root);

    const auto venv_dir = managed_venv_dir(tools_root, backend_id);
    auto venv_python = managed_venv_python(tools_root, backend_id);

    if (python_imports_module(venv_python, import_name))
    {
        emit_progress("ready", 100, venv_python, "already installed");
        return venv_python;
    }

    const auto system_python = host_python();
    if (system_python.isEmpty())
        throw std::runtime_error("python3 is required to install " + package.toStdString());

    auto make_line_cb = [&](const char* status, int percent, const QString& path,
                            const std::string& message) {
        return [=, &emit_progress](std::string_view line) {
            emit_progress(status, percent, path, message, std::string{line});
        };
    };

    if (!QFileInfo{venv_python}.exists())
    {
        emit_progress("extracting", 10, {}, fmt::format("creating virtualenv for {}", package.toStdString()));
        QDir{}.mkpath(QFileInfo{venv_dir}.absolutePath());
        run_python(system_python,
                   {"-m", "venv", venv_dir},
                   "python -m venv",
                   120000,
                   make_line_cb("extracting", 10, {}, "creating virtualenv"));
        venv_python = managed_venv_python(tools_root, backend_id);
        if (!QFileInfo{venv_python}.exists())
            throw std::runtime_error("virtualenv was created but python was not found inside it");
        ensure_executable(venv_python);
    }

    emit_progress("downloading", 25, venv_python, "upgrading pip");
    run_python(venv_python,
               {"-m", "pip", "install", "--upgrade", "pip"},
               "pip upgrade",
               300000,
               make_line_cb("downloading", 25, venv_python, "upgrading pip"));

    const auto install_msg = fmt::format("installing {}", package.toStdString());
    emit_progress("downloading", 45, venv_python, install_msg);
    run_python(venv_python,
               {"-m", "pip", "install", "--upgrade", package},
               fmt::format("pip install {}", package.toStdString()),
               900000,
               make_line_cb("downloading", 45, venv_python, install_msg));

    emit_progress("extracting", 90, venv_python, "verifying import");
    if (!python_imports_module(venv_python, import_name))
    {
        throw std::runtime_error(
            fmt::format("installed {} but `import {}` failed in the managed venv",
                        package.toStdString(),
                        import_name.toStdString()));
    }

    mpl::info(category, "installed {} into {}", package, venv_dir);
    emit_progress("ready", 100, venv_python, "installed");
    return venv_python;
}

void mp::llm::RuntimeInstaller::verify_archive(const RuntimeAsset& asset, const QString& archive_path)
{
    QString expected = asset.sha256_hex;
    if (asset.sha256_from_sidecar)
    {
        const auto sidecar_url = asset.url + ".sha256";
        const auto payload = downloader.download(QUrl{sidecar_url}, true);
        expected = parse_sha256_sidecar(payload);
    }
    if (expected.isEmpty())
        throw std::runtime_error("missing expected sha256 for managed tool archive");

    const auto actual = file_sha256_hex(archive_path);
    if (actual.compare(expected, Qt::CaseInsensitive) != 0)
    {
        throw std::runtime_error(fmt::format("checksum mismatch for {}: expected {}, got {}",
                                             asset.archive_name.toStdString(),
                                             expected.toStdString(),
                                             actual.toStdString()));
    }
}

void mp::llm::RuntimeInstaller::extract_archive(const QString& archive_path, const QString& dest_dir)
{
    QDir{}.mkpath(dest_dir);
    QProcess proc;
#ifdef Q_OS_WIN
    if (archive_is_zip(archive_path))
    {
        proc.start("powershell",
                   {"-NoProfile",
                    "-Command",
                    QStringLiteral("Expand-Archive -LiteralPath '%1' -DestinationPath '%2' -Force")
                        .arg(archive_path, dest_dir)});
    }
    else
    {
        proc.start("tar", {"-xf", archive_path, "-C", dest_dir});
    }
#else
    if (archive_is_zip(archive_path))
        proc.start("unzip", {"-o", archive_path, "-d", dest_dir});
    else
        proc.start("tar", {"-xzf", archive_path, "-C", dest_dir});
#endif
    if (!proc.waitForStarted(10000))
        throw std::runtime_error("failed to start archive extractor");
    if (!proc.waitForFinished(600000) || proc.exitCode() != 0)
    {
        throw std::runtime_error(
            fmt::format("archive extract failed: {}", proc.readAllStandardError().toStdString()));
    }
}

QString mp::llm::RuntimeInstaller::activate_extract(const RuntimeAsset& asset, const QString& staging_dir)
{
    const auto names = asset.tool_name == tool_llmfit
                           ? QStringList{QString::fromUtf8(tool_llmfit)}
                           : QStringList{QString::fromUtf8(tool_llama_server), "llama_server"};
    const auto found = find_binary_under(QDir{staging_dir}, names);
    if (found.isEmpty())
        throw std::runtime_error(fmt::format("extracted archive did not contain {}", asset.tool_name.toStdString()));

    const QFileInfo binary{found};
    // Prefer the directory that contains the binary (and sibling libs for llama.cpp).
    const auto payload_dir = binary.absolutePath();

    const auto tools_root = managed_tools_root(data_directory);
    const auto version_dir = managed_version_dir(tools_root, asset.tool_name);
    QDir{}.mkpath(QFileInfo{version_dir}.absolutePath());

    const auto staging_final = version_dir + ".staging";
    remove_path_recursively(staging_final);
    if (!copy_tree(payload_dir, staging_final))
        throw std::runtime_error("failed to stage managed tool files");

    remove_path_recursively(version_dir);
    if (!QDir{}.rename(staging_final, version_dir))
    {
        // Fallback if rename across devices fails.
        if (!copy_tree(staging_final, version_dir))
            throw std::runtime_error("failed to activate managed tool install");
        remove_path_recursively(staging_final);
    }

    const auto activated = find_in_managed(tools_root, asset.tool_name, names);
    if (activated.isEmpty())
        throw std::runtime_error("managed tool install activated but binary not found");
    ensure_executable(activated);
    return activated;
}

QString mp::llm::RuntimeInstaller::install_asset(const RuntimeAsset& asset,
                                                 const InstallProgressCallback& on_progress)
{
    auto emit_progress = [&](const char* status, int percent, const QString& path = {},
                             const std::string& message = {}) {
        if (on_progress)
            on_progress(InstallProgress{status, percent, path, message, {}});
    };

    emit_progress("downloading", 0, {}, fmt::format("downloading {}", asset.archive_name.toStdString()));

    QTemporaryDir tmp;
    if (!tmp.isValid())
        throw std::runtime_error("unable to create temporary directory for tool install");

    const auto archive_path = QDir{tmp.path()}.filePath(asset.archive_name);
    auto monitor = [&](int, int percent) {
        emit_progress("downloading", std::max(0, std::min(percent, 90)));
        return true;
    };
    downloader.download_to(QUrl{asset.url}, archive_path, -1, 0, monitor);

    emit_progress("downloading", 92, {}, "verifying checksum");
    verify_archive(asset, archive_path);

    emit_progress("extracting", 94, {}, "extracting archive");
    const auto extract_dir = QDir{tmp.path()}.filePath("extract");
    extract_archive(archive_path, extract_dir);

    emit_progress("extracting", 98, {}, "activating install");
    const auto binary = activate_extract(asset, extract_dir);

    if (!asset.companion_url.isEmpty())
    {
        emit_progress("downloading", 50, binary, "downloading CUDA runtime libraries");
        const auto companion_path = QDir{tmp.path()}.filePath(asset.companion_archive_name);
        auto companion_monitor = [&](int, int percent) {
            emit_progress("downloading", 50 + std::max(0, std::min(percent, 100)) * 40 / 100, binary,
                          "downloading CUDA runtime libraries");
            return true;
        };
        downloader.download_to(QUrl{asset.companion_url}, companion_path, -1, 0, companion_monitor);

        RuntimeAsset companion_check;
        companion_check.archive_name = asset.companion_archive_name;
        companion_check.sha256_hex = asset.companion_sha256_hex;
        companion_check.sha256_from_sidecar = false;
        emit_progress("downloading", 92, binary, "verifying CUDA runtime checksum");
        verify_archive(companion_check, companion_path);

        emit_progress("extracting", 95, binary, "extracting CUDA runtime libraries");
        const auto companion_extract = QDir{tmp.path()}.filePath("cudart-extract");
        extract_archive(companion_path, companion_extract);

        const auto version_dir =
            managed_version_dir(managed_tools_root(data_directory), asset.tool_name);
        const auto lib_dir = QFileInfo{binary}.absolutePath();
        copy_shared_libs_into(companion_extract, lib_dir.isEmpty() ? version_dir : lib_dir);
    }

    mpl::info(category, "installed {} at {}", asset.tool_name, binary);
    emit_progress("ready", 100, binary, "installed");
    return binary;
}
