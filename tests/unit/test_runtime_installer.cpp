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

#include "common.h"
#include "temp_dir.h"

#include "binary_locator.h"
#include "managed_tools.h"
#include "runtime_installer.h"

#include <multipass/constants.h>

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QProcessEnvironment>
#include <QUrl>

#include <stdexcept>

namespace mp = multipass;
namespace mpt = multipass::test;
namespace llm = multipass::llm;

using namespace testing;

namespace
{
void write_executable(const QString& path, const QByteArray& contents = "#!/bin/sh\necho ok\n")
{
    QDir{}.mkpath(QFileInfo{path}.absolutePath());
    QFile file{path};
    ASSERT_TRUE(file.open(QIODevice::WriteOnly));
    file.write(contents);
    file.close();
#ifndef Q_OS_WIN
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                        QFileDevice::ReadUser | QFileDevice::ExeUser);
#endif
}

class RecordingDownloader : public mp::URLDownloader
{
public:
    RecordingDownloader() : URLDownloader{std::chrono::milliseconds{1000}}
    {
    }

    void download_to(const QUrl& url,
                     const QString& file_name,
                     int64_t,
                     int,
                     const mp::ProgressMonitor& monitor) override
    {
        last_url = url;
        QDir{}.mkpath(QFileInfo{file_name}.absolutePath());
        QFile out{file_name};
        if (!out.open(QIODevice::WriteOnly))
            throw std::runtime_error("open failed");
        out.write(payload_for(url));
        out.close();
        if (monitor)
            monitor(0, 100);
    }

    QByteArray download(const QUrl& url) override
    {
        return download(url, false);
    }

    QByteArray download(const QUrl& url, bool) override
    {
        last_url = url;
        return payload_for(url);
    }

    QDateTime last_modified(const QUrl&) override
    {
        return {};
    }

    QUrl last_url;
    QByteArray archive_bytes{"archive-bytes"};
    QByteArray sha_bytes;

private:
    QByteArray payload_for(const QUrl& url) const
    {
        if (url.toString().endsWith(".sha256"))
            return sha_bytes;
        return archive_bytes;
    }
};
} // namespace

TEST(ManagedTools, rootAndVersionDir)
{
    mpt::TempDir dir;
    const auto root = llm::managed_tools_root(dir.path());
    EXPECT_TRUE(root.endsWith("llm/tools"));
    const auto llmfit_dir = llm::managed_version_dir(root, llm::tool_llmfit);
    EXPECT_TRUE(llmfit_dir.contains("llmfit"));
    EXPECT_TRUE(llmfit_dir.contains(llm::pinned_llmfit_version));
}

TEST(ManagedTools, findInManagedLocatesPinnedBinary)
{
    mpt::TempDir dir;
    const auto root = llm::managed_tools_root(dir.path());
    const auto version_dir = llm::managed_version_dir(root, llm::tool_llmfit);
    write_executable(QDir{version_dir}.filePath("llmfit"));

    const auto found = llm::find_in_managed(root, llm::tool_llmfit, {"llmfit"});
    EXPECT_FALSE(found.isEmpty());
    EXPECT_TRUE(llm::is_under_managed_tools(found, root));
}

TEST(BinaryLocator, precedenceEnvOverManagedOverPath)
{
    mpt::TempDir dir;
    const auto root = llm::managed_tools_root(dir.path());
    const auto managed_bin = QDir{llm::managed_version_dir(root, llm::tool_llmfit)}.filePath("llmfit");
    write_executable(managed_bin);

    mpt::TempDir env_dir;
    const auto env_bin = env_dir.filePath("llmfit-env");
    write_executable(env_bin);

    qputenv(mp::llmfit_env_var, env_bin.toUtf8());
    const auto via_env =
        llm::locate_binary(mp::llmfit_env_var, {"llmfit"}, root, llm::tool_llmfit);
    EXPECT_EQ(via_env, QFileInfo{env_bin}.absoluteFilePath());

    qunsetenv(mp::llmfit_env_var);
    const auto via_managed =
        llm::locate_binary(mp::llmfit_env_var, {"llmfit"}, root, llm::tool_llmfit);
    EXPECT_EQ(via_managed, QFileInfo{managed_bin}.absoluteFilePath());
}

TEST(RuntimeInstaller, resolveLlmfitAssetUrl)
{
    const auto asset = llm::resolve_runtime_asset("llmfit");
    EXPECT_EQ(asset.tool_name, llm::tool_llmfit);
    EXPECT_TRUE(asset.url.contains("AlexsJones/llmfit/releases/download"));
    EXPECT_TRUE(asset.url.contains(llm::pinned_llmfit_version));
    EXPECT_TRUE(asset.sha256_from_sidecar);
}

TEST(RuntimeInstaller, resolveLlamacppAssetUrl)
{
    const auto asset = llm::resolve_runtime_asset("llamacpp");
    EXPECT_EQ(asset.tool_name, llm::tool_llama_server);
    EXPECT_TRUE(asset.url.contains("ggml-org/llama.cpp/releases/download"));
    EXPECT_TRUE(asset.url.contains(llm::pinned_llama_build));
    EXPECT_EQ(asset.sha256_hex.size(), 64);
    EXPECT_FALSE(asset.sha256_from_sidecar);
}

TEST(RuntimeInstaller, unknownBackendThrows)
{
    EXPECT_THROW(llm::resolve_runtime_asset("ollama"), std::runtime_error);
}

TEST(RuntimeInstaller, checksumMismatchThrows)
{
    mpt::TempDir dir;
    RecordingDownloader downloader;
    downloader.archive_bytes = "not-matching";
    downloader.sha_bytes = QByteArray{"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  file\n"};

    llm::RuntimeInstaller installer{downloader, dir.path()};
    EXPECT_THROW(installer.install("llmfit"), std::runtime_error);
}

TEST(RuntimeInstaller, matchingChecksumInstallsLlmfitArchive)
{
    mpt::TempDir dir;
    RecordingDownloader downloader;

    // Build a tiny tar.gz containing llmfit.
    mpt::TempDir payload;
    const auto bin = payload.filePath("llmfit");
    write_executable(bin, "#!/bin/sh\necho llmfit\n");

    mpt::TempDir archive_dir;
    const auto tar_path = archive_dir.filePath("llmfit.tgz");
    {
        QProcess tar;
        tar.setWorkingDirectory(payload.path());
        tar.start("tar", {"-czf", tar_path, "llmfit"});
        ASSERT_TRUE(tar.waitForFinished(10000));
        ASSERT_EQ(tar.exitCode(), 0);
    }

    QFile tar_file{tar_path};
    ASSERT_TRUE(tar_file.open(QIODevice::ReadOnly));
    downloader.archive_bytes = tar_file.readAll();
    tar_file.close();

    const auto digest = QCryptographicHash::hash(downloader.archive_bytes, QCryptographicHash::Sha256).toHex();
    downloader.sha_bytes = digest + "  llmfit.tgz\n";

    // Force resolve to use our downloaded bytes by installing through installer;
    // the installer builds its own URL but RecordingDownloader ignores URL body.
    // Override: temporarily not possible without DI of asset. Instead, call install
    // and let verify use sidecar — URL name does not matter for RecordingDownloader.
    llm::RuntimeInstaller installer{downloader, dir.path()};

    // install() uses real asset URL/name; download_to writes archive_bytes to that filename.
    // Extract expects tar.gz; our bytes are a real tar.gz. Good.
    QString path;
    EXPECT_NO_THROW(path = installer.install("llmfit"));
    EXPECT_FALSE(path.isEmpty());
    EXPECT_TRUE(QFileInfo{path}.isExecutable());
}
