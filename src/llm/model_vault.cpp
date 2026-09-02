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

#include "model_vault.h"

#include <multipass/file_ops.h>
#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/utils.h>
#include <multipass/vm_image_vault.h>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>

#include <algorithm>
#include <stdexcept>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
bool is_sharded_gguf(const std::string& filename)
{
    return filename.find("-of-") != std::string::npos;
}

bool looks_like_gguf(const QString& path)
{
    QFileInfo info{path};
    if (!info.exists() || info.size() < 1024 * 1024)
        return false;
    QFile file{path};
    if (!file.open(QIODevice::ReadOnly))
        return false;
    return file.read(4) == "GGUF";
}

QUrl huggingface_file_url(const std::string& repo, const std::string& filename)
{
    QUrl url;
    url.setScheme("https");
    url.setHost("huggingface.co");
    url.setPath(QString::fromStdString(fmt::format("/{}/resolve/main/{}", repo, filename)));
    return url;
}

std::string sanitize_repo(const std::string& repo)
{
    auto out = repo;
    for (auto& c : out)
    {
        if (c == '/' || c == '\\')
            c = '_';
    }
    return out;
}
} // namespace

mp::ModelVault::ModelVault(Path data_directory, URLDownloader& downloader)
    : downloader{downloader}
{
    QDir dir{data_directory};
    dir.mkpath("vault/models");
    root = dir.filePath("vault/models");
    index_path = QDir{root}.filePath("index.json");
    load();
}

std::optional<mp::ModelArtifact> mp::ModelVault::find(const std::string& model_id) const
{
    for (const auto& art : artifacts)
    {
        if (art.id == model_id || art.filename == model_id)
            return art;
    }
    return std::nullopt;
}

std::vector<mp::ModelArtifact> mp::ModelVault::list() const
{
    return artifacts;
}

mp::Path mp::ModelVault::models_root() const
{
    return root;
}

mp::Path mp::ModelVault::artifact_path(const std::string& repo, const std::string& filename) const
{
    QDir dest{QDir{root}.filePath(QString::fromStdString(sanitize_repo(repo)))};
    dest.mkpath(".");
    return dest.filePath(QString::fromStdString(filename));
}

mp::ModelArtifact mp::ModelVault::pull(const std::string& model_id,
                                       const std::string& repo,
                                       const std::string& filename,
                                       const std::string& quant,
                                       const std::string& hf_token,
                                       const ProgressMonitor& monitor)
{
    if (filename.empty() || repo.empty())
        throw std::runtime_error("model resolve did not produce a Hugging Face repo and filename");
    if (is_sharded_gguf(filename))
        throw std::runtime_error(
            "sharded/split GGUF is not supported; pick a single-file quantization");

    if (auto existing = find(model_id))
    {
        if (looks_like_gguf(QString::fromStdString(existing->path)))
        {
            touch(model_id);
            return *find(model_id);
        }
        QFile::remove(QString::fromStdString(existing->path));
    }

    const auto dest = artifact_path(repo, filename);
    if (QFileInfo{dest}.exists() && looks_like_gguf(dest))
    {
        ModelArtifact art;
        art.id = model_id;
        art.repo = repo;
        art.filename = filename;
        art.quant = quant;
        art.path = dest.toStdString();
        art.size_bytes = QFileInfo{dest}.size();
        art.last_accessed = QDateTime::currentSecsSinceEpoch();
        artifacts.erase(std::remove_if(artifacts.begin(),
                                       artifacts.end(),
                                       [&](const auto& a) { return a.id == model_id; }),
                        artifacts.end());
        artifacts.push_back(art);
        save();
        return art;
    }
    if (QFileInfo{dest}.exists())
        QFile::remove(dest);

    const auto parent = QFileInfo{dest}.absolutePath();
    const auto available = MP_UTILS.filesystem_bytes_available(parent);
    if (available >= 0 && available < 256LL * 1024 * 1024)
        throw std::runtime_error("not enough disk space to download the model");

    const auto url = huggingface_file_url(repo, filename);
    mpl::info("llm", "downloading {} -> {}", url.toString(), dest);

    downloader.clear_headers();
    if (!hf_token.empty())
        downloader.set_header("Authorization",
                              QByteArray{"Bearer "} + QByteArray::fromStdString(hf_token));

    mp::vault::DeleteOnException guard{dest.toStdString()};
    try
    {
        downloader.download_to(url, dest, -1, 0, monitor);
    }
    catch (...)
    {
        downloader.clear_headers();
        throw;
    }
    downloader.clear_headers();

    if (!looks_like_gguf(dest))
    {
        QFile::remove(dest);
        throw std::runtime_error(
            "downloaded file is not a GGUF; the Hugging Face URL is missing or returned HTML");
    }

    ModelArtifact art;
    art.id = model_id;
    art.repo = repo;
    art.filename = filename;
    art.quant = quant;
    art.path = dest.toStdString();
    art.size_bytes = QFileInfo{dest}.size();
    art.last_accessed = QDateTime::currentSecsSinceEpoch();
    artifacts.push_back(art);
    save();
    return art;
}

bool mp::ModelVault::remove(const std::string& model_id)
{
    auto it = std::find_if(artifacts.begin(), artifacts.end(), [&](const auto& a) {
        return a.id == model_id;
    });
    if (it == artifacts.end())
        return false;
    const auto path = QString::fromStdString(it->path);
    const auto parent = QFileInfo{path}.absoluteDir();
    QFile::remove(path);
    artifacts.erase(it);
    save();
    if (parent.exists() && parent.isEmpty())
        parent.rmdir(".");
    return true;
}

void mp::ModelVault::touch(const std::string& model_id)
{
    for (auto& art : artifacts)
    {
        if (art.id == model_id)
        {
            art.last_accessed = QDateTime::currentSecsSinceEpoch();
            save();
            return;
        }
    }
}

void mp::ModelVault::load()
{
    artifacts.clear();
    QFile file{index_path};
    if (!file.exists() || !file.open(QIODevice::ReadOnly))
        return;
    const auto doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isArray())
        return;
    for (const auto& item : doc.array())
    {
        if (!item.isObject())
            continue;
        const auto obj = item.toObject();
        ModelArtifact art;
        art.id = obj.value("id").toString().toStdString();
        art.repo = obj.value("repo").toString().toStdString();
        art.filename = obj.value("filename").toString().toStdString();
        art.quant = obj.value("quant").toString().toStdString();
        art.path = obj.value("path").toString().toStdString();
        art.size_bytes = static_cast<long long>(obj.value("size_bytes").toDouble());
        art.last_accessed = static_cast<long long>(obj.value("last_accessed").toDouble());
        if (!art.id.empty())
            artifacts.push_back(std::move(art));
    }
}

void mp::ModelVault::save() const
{
    QJsonArray array;
    for (const auto& art : artifacts)
    {
        QJsonObject obj;
        obj.insert("id", QString::fromStdString(art.id));
        obj.insert("repo", QString::fromStdString(art.repo));
        obj.insert("filename", QString::fromStdString(art.filename));
        obj.insert("quant", QString::fromStdString(art.quant));
        obj.insert("path", QString::fromStdString(art.path));
        obj.insert("size_bytes", static_cast<double>(art.size_bytes));
        obj.insert("last_accessed", static_cast<double>(art.last_accessed));
        array.append(obj);
    }
    MP_FILEOPS.write_transactionally(index_path,
                                     QJsonDocument{array}.toJson(QJsonDocument::Indented));
}
