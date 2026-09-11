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
#include <multipass/progress_monitor.h>
#include <multipass/url_downloader.h>

#include <optional>
#include <string>
#include <vector>

namespace multipass
{

struct ModelArtifact
{
    std::string id;
    std::string repo;
    std::string filename;
    std::string quant;
    std::string path;
    std::string mmproj_filename;
    std::string mmproj_path;
    long long size_bytes{0};
    long long last_accessed{0};
};

class ModelVault
{
public:
    ModelVault(Path data_directory, URLDownloader& downloader);

    std::optional<ModelArtifact> find(const std::string& model_id) const;
    std::vector<ModelArtifact> list() const;
    Path models_root() const;

    ModelArtifact pull(const std::string& model_id,
                       const std::string& repo,
                       const std::string& filename,
                       const std::string& quant,
                       const std::string& hf_token,
                       const ProgressMonitor& monitor,
                       const std::string& mmproj_filename = {});

    bool remove(const std::string& model_id);
    void touch(const std::string& model_id);
    void forget_index(const std::string& model_id);
    ModelArtifact attach_mmproj(const std::string& model_id, const std::string& mmproj_path);

    ModelArtifact ensure_mmproj(const std::string& model_id,
                                const std::string& repo,
                                const std::string& mmproj_filename,
                                const std::string& hf_token,
                                const ProgressMonitor& monitor);

private:
    void load();
    void save() const;
    Path artifact_path(const std::string& repo, const std::string& filename) const;

    Path root;
    Path index_path;
    URLDownloader& downloader;
    std::vector<ModelArtifact> artifacts;
};

} // namespace multipass
