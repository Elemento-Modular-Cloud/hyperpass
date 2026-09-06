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

#include <multipass/format.h>
#include <multipass/logging/log.h>

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QSysInfo>
#include <QTemporaryDir>
#include <QUrl>

#include <algorithm>
#include <stdexcept>
#include <unordered_map>

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
} // namespace

QString mp::llm::backend_id_to_tool_name(const QString& backend_id)
{
    if (backend_id == "llmfit")
        return QString::fromUtf8(tool_llmfit);
    if (backend_id == "llamacpp")
        return QString::fromUtf8(tool_llama_server);
    return {};
}

mp::llm::RuntimeAsset mp::llm::resolve_runtime_asset(const QString& backend_id)
{
    const auto tool = backend_id_to_tool_name(backend_id);
    if (tool.isEmpty())
        throw std::runtime_error(fmt::format("unknown backend id '{}'; expected llmfit or llamacpp",
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

QString mp::llm::RuntimeInstaller::install(const QString& backend_id,
                                           const InstallProgressCallback& on_progress)
{
    const auto asset = resolve_runtime_asset(backend_id);
    const auto names = asset.tool_name == tool_llmfit
                           ? QStringList{QString::fromUtf8(tool_llmfit)}
                           : QStringList{QString::fromUtf8(tool_llama_server), "llama_server"};
    const auto tools_root = managed_tools_root(data_directory);
    const auto existing = find_in_managed(tools_root, asset.tool_name, names);
    if (!existing.isEmpty())
    {
        if (on_progress)
            on_progress(InstallProgress{"ready", 100, existing, "already installed"});
        return existing;
    }
    return install_asset(asset, on_progress);
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
            on_progress(InstallProgress{status, percent, path, message});
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
    mpl::info(category, "installed {} at {}", asset.tool_name, binary);
    emit_progress("ready", 100, binary, "installed");
    return binary;
}
