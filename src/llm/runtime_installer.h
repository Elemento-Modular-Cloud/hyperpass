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

#pragma once

#include <multipass/path.h>
#include <multipass/url_downloader.h>

#include <QString>

#include <functional>
#include <string>

namespace multipass::llm
{

struct RuntimeAsset
{
    QString tool_name; // llmfit | llama-server
    QString version;
    QString url;
    QString sha256_hex;      // empty → fetch .sha256 sidecar (llmfit) or fail
    bool sha256_from_sidecar{false};
    QString archive_name;
};

struct InstallProgress
{
    std::string status; // downloading | extracting | ready | error
    int percent{0};
    QString binary_path;
    std::string message;
};

using InstallProgressCallback = std::function<void(const InstallProgress&)>;

RuntimeAsset resolve_runtime_asset(const QString& backend_id);
QString backend_id_to_tool_name(const QString& backend_id);

class RuntimeInstaller
{
public:
    RuntimeInstaller(URLDownloader& downloader, Path data_directory);

    QString install(const QString& backend_id, const InstallProgressCallback& on_progress = {});

private:
    QString install_asset(const RuntimeAsset& asset, const InstallProgressCallback& on_progress);
    void verify_archive(const RuntimeAsset& asset, const QString& archive_path);
    void extract_archive(const QString& archive_path, const QString& dest_dir);
    QString activate_extract(const RuntimeAsset& asset, const QString& staging_dir);

    URLDownloader& downloader;
    Path data_directory;
};

} // namespace multipass::llm
