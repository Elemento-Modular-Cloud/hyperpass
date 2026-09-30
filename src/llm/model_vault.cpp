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
#include "gguf_file_pick.h"
#include "runners/model_format.h"

#include <multipass/file_ops.h>
#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/utils.h>
#include <multipass/vm_image_vault.h>

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>
#include <QUrlQuery>

#include <algorithm>
#include <stdexcept>

namespace mp = multipass;
namespace mpl = multipass::logging;
namespace llm = multipass::llm;

namespace
{
bool is_sharded_gguf(const std::string& filename)
{
    return filename.find("-of-") != std::string::npos;
}

bool looks_like_gguf(const QString& path, qint64 min_size = 1024 * 1024)
{
    QFileInfo info{path};
    if (!info.exists() || info.size() < min_size)
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

bool looks_like_local_hub_snapshot(const QString& path)
{
    const QFileInfo info{path};
    if (!info.exists() || !info.isDir())
        return false;
    // MLX / HF checkpoints always ship config.json once the snapshot is complete enough to load.
    return QFileInfo{QDir{path}.filePath(QStringLiteral("config.json"))}.exists();
}

struct HubTreeEntry
{
    QString path;
    qint64 size{0};
};

std::vector<HubTreeEntry> parse_hub_tree(const QByteArray& payload)
{
    const auto doc = QJsonDocument::fromJson(payload);
    if (!doc.isArray())
        throw std::runtime_error("Hugging Face tree listing is not a JSON array");

    std::vector<HubTreeEntry> files;
    for (const auto& value : doc.array())
    {
        if (!value.isObject())
            continue;
        const auto obj = value.toObject();
        if (obj.value("type").toString() != QLatin1String("file"))
            continue;
        const auto rel = obj.value("path").toString();
        if (rel.isEmpty() || rel.startsWith(QLatin1String(".git")))
            continue;
        HubTreeEntry entry;
        entry.path = rel;
        entry.size = static_cast<qint64>(obj.value("size").toDouble());
        files.push_back(std::move(entry));
    }
    return files;
}

QUrl huggingface_tree_url(const std::string& repo)
{
    QUrl url;
    url.setScheme("https");
    url.setHost("huggingface.co");
    url.setPath(QString::fromStdString(fmt::format("/api/models/{}/tree/main", repo)));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("recursive"), QStringLiteral("1"));
    url.setQuery(query);
    return url;
}

long long directory_byte_size(const QString& path)
{
    long long total = 0;
    QDirIterator it{path,
                    QDir::Files,
                    QDirIterator::Subdirectories};
    while (it.hasNext())
    {
        it.next();
        total += it.fileInfo().size();
    }
    return total;
}
} // namespace

std::string mp::ModelVault::effective_format(const ModelArtifact& art)
{
    if (!art.format.empty())
        return art.format;
    return llm::format_gguf;
}

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
    std::optional<ModelArtifact> best;
    for (const auto& art : artifacts)
    {
        if (art.id != model_id && art.filename != model_id)
            continue;
        if (!best || art.last_accessed > best->last_accessed)
            best = art;
    }
    return best;
}

std::optional<mp::ModelArtifact> mp::ModelVault::find(const std::string& model_id,
                                                      const std::string& format) const
{
    return find(model_id, format, {});
}

std::optional<mp::ModelArtifact> mp::ModelVault::find(const std::string& model_id,
                                                      const std::string& format,
                                                      const std::string& quant) const
{
    const auto want = format.empty() ? llm::format_gguf : format;
    std::vector<const ModelArtifact*> matches;
    for (const auto& art : artifacts)
    {
        if ((art.id == model_id || art.filename == model_id) && effective_format(art) == want)
            matches.push_back(&art);
    }
    if (matches.empty())
        return std::nullopt;

    if (!quant.empty())
    {
        for (const auto* art : matches)
        {
            if (QString::fromStdString(art->quant).compare(QString::fromStdString(quant),
                                                           Qt::CaseInsensitive) == 0)
                return *art;
        }
        return std::nullopt;
    }

    auto preferred = [&](const QString& tag) -> std::optional<ModelArtifact> {
        for (const auto* art : matches)
        {
            if (QString::fromStdString(art->quant).compare(tag, Qt::CaseInsensitive) == 0)
                return *art;
        }
        return std::nullopt;
    };
    for (const auto& pref : {"Q4_K_M", "Q5_K_M", "Q6_K", "Q4_K_S", "Q8_0", "Q4_0"})
    {
        if (auto hit = preferred(pref))
            return hit;
    }

    const ModelArtifact* newest = matches.front();
    for (const auto* art : matches)
    {
        if (art->last_accessed > newest->last_accessed)
            newest = art;
    }
    return *newest;
}

std::vector<mp::ModelArtifact> mp::ModelVault::list() const
{
    return artifacts;
}

std::vector<mp::ModelArtifact> mp::ModelVault::list_for(const std::string& model_id) const
{
    std::vector<ModelArtifact> out;
    for (const auto& art : artifacts)
    {
        if (art.id == model_id)
            out.push_back(art);
    }
    return out;
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

mp::ModelArtifact mp::ModelVault::register_remote(const std::string& model_id,
                                                  const std::string& repo,
                                                  const std::string& format,
                                                  const std::string& quant)
{
    if (model_id.empty() || repo.empty())
        throw std::runtime_error("model resolve did not produce a Hugging Face repo");
    if (format != llm::format_hf && format != llm::format_mlx)
        throw std::runtime_error(
            fmt::format("register_remote expects hf or mlx format, got '{}'", format));

    if (auto existing = find(model_id, format))
    {
        touch(model_id);
        return *find(model_id, format);
    }

    ModelArtifact art;
    art.id = model_id;
    art.repo = repo;
    art.filename = "";
    art.quant = quant;
    art.path = repo;
    art.format = format;
    art.size_bytes = 0;
    art.last_accessed = QDateTime::currentSecsSinceEpoch();

    artifacts.erase(std::remove_if(artifacts.begin(),
                                   artifacts.end(),
                                   [&](const auto& a) {
                                       return a.id == model_id && effective_format(a) == format;
                                   }),
                    artifacts.end());
    artifacts.push_back(art);
    save();
    return art;
}

mp::ModelArtifact mp::ModelVault::pull_remote(const std::string& model_id,
                                              const std::string& repo,
                                              const std::string& format,
                                              const std::string& quant,
                                              const std::string& hf_token,
                                              const ProgressMonitor& monitor)
{
    if (model_id.empty() || repo.empty())
        throw std::runtime_error("model resolve did not produce a Hugging Face repo");
    if (format != llm::format_hf && format != llm::format_mlx)
        throw std::runtime_error(
            fmt::format("pull_remote expects hf or mlx format, got '{}'", format));

    if (auto existing = find(model_id, format, quant))
    {
        if (existing->repo == repo && looks_like_local_hub_snapshot(QString::fromStdString(existing->path)))
        {
            touch(model_id);
            return *find(model_id, format, quant);
        }
    }
    // Also accept an existing local snapshot registered without quant match.
    if (auto existing = find(model_id, format))
    {
        if (existing->repo == repo && looks_like_local_hub_snapshot(QString::fromStdString(existing->path)))
        {
            touch(model_id);
            return *existing;
        }
        // Stale remote-only row or wrong repo — drop before re-download.
        forget_index(model_id, format);
    }

    const auto dest_root = QDir{root}.filePath(QString::fromStdString(sanitize_repo(repo)));
    QDir{}.mkpath(dest_root);

    downloader.clear_headers();
    if (!hf_token.empty())
        downloader.set_header("Authorization",
                              QByteArray{"Bearer "} + QByteArray::fromStdString(hf_token));

    std::vector<HubTreeEntry> files;
    try
    {
        const auto listing = downloader.download(huggingface_tree_url(repo));
        files = parse_hub_tree(listing);
    }
    catch (...)
    {
        downloader.clear_headers();
        throw;
    }

    if (files.empty())
    {
        downloader.clear_headers();
        throw std::runtime_error(
            fmt::format("Hugging Face repo '{}' has no downloadable files", repo));
    }

    qint64 total_bytes = 0;
    for (const auto& file : files)
        total_bytes += std::max<qint64>(file.size, 0);
    if (total_bytes <= 0)
        total_bytes = static_cast<qint64>(files.size());

    mpl::info("llm",
              "downloading {} ({} files, {:.1f} GiB) -> {}",
              repo,
              files.size(),
              static_cast<double>(total_bytes) / (1024.0 * 1024.0 * 1024.0),
              dest_root);

    qint64 completed_bytes = 0;
    try
    {
        for (size_t i = 0; i < files.size(); ++i)
        {
            const auto& file = files[i];
            const auto dest = QDir{dest_root}.filePath(file.path);
            QDir{}.mkpath(QFileInfo{dest}.absolutePath());

            const auto existing_size = QFileInfo{dest}.exists() ? QFileInfo{dest}.size() : 0;
            if (file.size > 0 && existing_size == file.size)
            {
                completed_bytes += file.size;
                if (monitor &&
                    !monitor(0,
                             static_cast<int>(std::min<qint64>(
                                 99, (completed_bytes * 100) / total_bytes))))
                {
                    downloader.clear_headers();
                    throw std::runtime_error("download cancelled");
                }
                continue;
            }

            const auto url = huggingface_file_url(repo, file.path.toStdString());
            const auto file_weight = file.size > 0 ? file.size : 1;
            auto file_monitor = [&](int, int progress) {
                if (!monitor)
                    return true;
                qint64 portion = 0;
                if (progress >= 0)
                    portion = (file_weight * std::clamp(progress, 0, 100)) / 100;
                const auto overall =
                    static_cast<int>(std::min<qint64>(
                        99, ((completed_bytes + portion) * 100) / total_bytes));
                return monitor(0, overall);
            };

            if (QFileInfo{dest}.exists())
                QFile::remove(dest);

            downloader.download_to(url, dest, file.size > 0 ? file.size : -1, 0, file_monitor);
            completed_bytes += file_weight;

            if (monitor &&
                !monitor(0,
                         static_cast<int>(std::min<qint64>(
                             99, (completed_bytes * 100) / total_bytes))))
            {
                downloader.clear_headers();
                throw std::runtime_error("download cancelled");
            }
        }
    }
    catch (...)
    {
        downloader.clear_headers();
        throw;
    }
    downloader.clear_headers();

    if (!looks_like_local_hub_snapshot(dest_root))
        throw std::runtime_error(fmt::format(
            "downloaded snapshot for '{}' is incomplete (missing config.json)", repo));

    if (monitor)
        monitor(0, 100);

    ModelArtifact art;
    art.id = model_id;
    art.repo = repo;
    art.filename = "";
    art.quant = quant;
    art.path = dest_root.toStdString();
    art.format = format;
    art.size_bytes = directory_byte_size(dest_root);
    art.last_accessed = QDateTime::currentSecsSinceEpoch();
    artifacts.push_back(art);
    save();
    return art;
}

mp::ModelArtifact mp::ModelVault::pull(const std::string& model_id,
                                       const std::string& repo,
                                       const std::string& filename,
                                       const std::string& quant,
                                       const std::string& hf_token,
                                       const ProgressMonitor& monitor,
                                       const std::string& mmproj_filename)
{
    if (filename.empty() || repo.empty())
        throw std::runtime_error("model resolve did not produce a Hugging Face repo and filename");
    if (is_sharded_gguf(filename) || is_sharded_gguf_name(QString::fromStdString(filename)))
        throw std::runtime_error(
            "sharded/split GGUF is not supported; pick a single-file quantization");
    if (is_mmproj_gguf(QString::fromStdString(filename)))
        throw std::runtime_error(
            "refusing to store a CLIP mmproj projector as the main GGUF; load it with --mmproj");

    const auto effective_quant =
        quant.empty() ? infer_quant_from_gguf_filename(QString::fromStdString(filename)).toStdString()
                      : quant;

    if (auto existing = find(model_id, llm::format_gguf, effective_quant))
    {
        const auto existing_name = QFileInfo{QString::fromStdString(existing->path)}.fileName();
        const bool same_file =
            QString::fromStdString(existing->filename)
                    .compare(QString::fromStdString(filename), Qt::CaseInsensitive) == 0 ||
            existing_name.compare(QString::fromStdString(filename), Qt::CaseInsensitive) == 0;
        if (!is_mmproj_gguf(QString::fromStdString(existing->filename)) &&
            !is_mmproj_gguf(existing_name) &&
            looks_like_gguf(QString::fromStdString(existing->path)) && same_file)
        {
            touch(model_id);
            if (!mmproj_filename.empty() && existing->mmproj_path.empty())
                return ensure_mmproj(model_id, repo, mmproj_filename, hf_token, monitor);
            return *find(model_id, llm::format_gguf, effective_quant);
        }
    }

    // Drop a stale same-quant index row (wrong/corrupt file) but keep other quants.
    if (!effective_quant.empty())
        forget_index(model_id, llm::format_gguf, effective_quant);

    const auto dest = artifact_path(repo, filename);
    if (!(QFileInfo{dest}.exists() && looks_like_gguf(dest)))
    {
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
    }

    ModelArtifact art;
    art.id = model_id;
    art.repo = repo;
    art.filename = filename;
    art.quant = effective_quant;
    art.path = dest.toStdString();
    art.format = llm::format_gguf;
    art.size_bytes = QFileInfo{dest}.size();
    art.last_accessed = QDateTime::currentSecsSinceEpoch();
    artifacts.erase(std::remove_if(artifacts.begin(),
                                   artifacts.end(),
                                   [&](const auto& a) {
                                       if (a.id != model_id ||
                                           effective_format(a) != llm::format_gguf)
                                           return false;
                                       if (!effective_quant.empty() &&
                                           QString::fromStdString(a.quant).compare(
                                               QString::fromStdString(effective_quant),
                                               Qt::CaseInsensitive) == 0)
                                           return true;
                                       return QString::fromStdString(a.filename)
                                                  .compare(QString::fromStdString(filename),
                                                           Qt::CaseInsensitive) == 0;
                                   }),
                    artifacts.end());
    artifacts.push_back(art);
    save();

    if (!mmproj_filename.empty())
        return ensure_mmproj(model_id, repo, mmproj_filename, hf_token, monitor);

    if (auto sibling = find_sibling_mmproj(dest); !sibling.isEmpty())
        return attach_mmproj(model_id, effective_quant, sibling.toStdString());

    return art;
}

bool mp::ModelVault::remove(const std::string& model_id)
{
    auto matches = list_for(model_id);
    if (matches.empty())
        return false;
    for (const auto& art : matches)
        remove(model_id, effective_format(art));
    return true;
}

bool mp::ModelVault::remove(const std::string& model_id, const std::string& format)
{
    std::vector<std::string> quants;
    for (const auto& art : artifacts)
    {
        if (art.id == model_id && effective_format(art) == format)
            quants.push_back(art.quant);
    }
    if (quants.empty())
        return false;
    bool removed_any = false;
    for (const auto& q : quants)
        removed_any = remove(model_id, format, q) || removed_any;
    return removed_any;
}

bool mp::ModelVault::remove(const std::string& model_id,
                            const std::string& format,
                            const std::string& quant)
{
    auto it = std::find_if(artifacts.begin(), artifacts.end(), [&](const auto& a) {
        if (a.id != model_id || effective_format(a) != format)
            return false;
        if (quant.empty())
            return true;
        return QString::fromStdString(a.quant).compare(QString::fromStdString(quant),
                                                       Qt::CaseInsensitive) == 0;
    });
    if (it == artifacts.end())
        return false;
    const auto path = QString::fromStdString(it->path);
    const auto mmproj = QString::fromStdString(it->mmproj_path);
    if (QFileInfo{path}.isDir())
    {
        QDir{path}.removeRecursively();
    }
    else if (effective_format(*it) == llm::format_gguf || QFileInfo{path}.exists())
    {
        const auto parent = QFileInfo{path}.absoluteDir();
        if (QFileInfo{path}.isFile())
            QFile::remove(path);
        if (!mmproj.isEmpty() && mmproj != path)
            QFile::remove(mmproj);
        if (parent.exists() && parent.isEmpty())
            parent.rmdir(".");
    }
    artifacts.erase(it);
    save();
    return true;
}

void mp::ModelVault::forget_index(const std::string& model_id)
{
    const auto before = artifacts.size();
    artifacts.erase(std::remove_if(artifacts.begin(),
                                   artifacts.end(),
                                   [&](const auto& a) { return a.id == model_id; }),
                    artifacts.end());
    if (artifacts.size() != before)
        save();
}

void mp::ModelVault::forget_index(const std::string& model_id, const std::string& format)
{
    const auto before = artifacts.size();
    artifacts.erase(std::remove_if(artifacts.begin(),
                                   artifacts.end(),
                                   [&](const auto& a) {
                                       return a.id == model_id && effective_format(a) == format;
                                   }),
                    artifacts.end());
    if (artifacts.size() != before)
        save();
}

void mp::ModelVault::forget_index(const std::string& model_id,
                                  const std::string& format,
                                  const std::string& quant)
{
    const auto before = artifacts.size();
    artifacts.erase(std::remove_if(artifacts.begin(),
                                   artifacts.end(),
                                   [&](const auto& a) {
                                       if (a.id != model_id || effective_format(a) != format)
                                           return false;
                                       if (quant.empty())
                                           return true;
                                       return QString::fromStdString(a.quant).compare(
                                                  QString::fromStdString(quant),
                                                  Qt::CaseInsensitive) == 0;
                                   }),
                    artifacts.end());
    if (artifacts.size() != before)
        save();
}

mp::ModelArtifact mp::ModelVault::attach_mmproj(const std::string& model_id,
                                                const std::string& mmproj_path)
{
    return attach_mmproj(model_id, {}, mmproj_path);
}

mp::ModelArtifact mp::ModelVault::attach_mmproj(const std::string& model_id,
                                                const std::string& quant,
                                                const std::string& mmproj_path)
{
    if (auto art = find(model_id, llm::format_gguf, quant))
    {
        for (auto& entry : artifacts)
        {
            if (entry.id != model_id || effective_format(entry) != llm::format_gguf)
                continue;
            if (!quant.empty() &&
                QString::fromStdString(entry.quant).compare(QString::fromStdString(quant),
                                                            Qt::CaseInsensitive) != 0)
                continue;
            if (quant.empty() && entry.path != art->path)
                continue;
            entry.mmproj_path = mmproj_path;
            entry.mmproj_filename =
                QFileInfo{QString::fromStdString(mmproj_path)}.fileName().toStdString();
            entry.last_accessed = QDateTime::currentSecsSinceEpoch();
            save();
            return entry;
        }
    }
    throw std::runtime_error(
        fmt::format("cannot attach mmproj: model '{}' is not in the vault", model_id));
}

mp::ModelArtifact mp::ModelVault::ensure_mmproj(const std::string& model_id,
                                                const std::string& repo,
                                                const std::string& mmproj_filename,
                                                const std::string& hf_token,
                                                const ProgressMonitor& monitor)
{
    auto existing = find(model_id, llm::format_gguf);
    if (!existing)
        throw std::runtime_error(
            fmt::format("cannot download mmproj: model '{}' is not in the vault", model_id));
    if (!existing->mmproj_path.empty() &&
        looks_like_gguf(QString::fromStdString(existing->mmproj_path), 64 * 1024))
        return *existing;

    const auto dest = artifact_path(repo, mmproj_filename);
    if (!(QFileInfo{dest}.exists() && looks_like_gguf(dest, 64 * 1024)))
    {
        if (QFileInfo{dest}.exists())
            QFile::remove(dest);

        const auto url = huggingface_file_url(repo, mmproj_filename);
        mpl::info("llm", "downloading mmproj {} -> {}", url.toString(), dest);

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
        if (!looks_like_gguf(dest, 64 * 1024))
        {
            QFile::remove(dest);
            throw std::runtime_error("downloaded mmproj is not a GGUF");
        }
    }
    return attach_mmproj(model_id, dest.toStdString());
}

void mp::ModelVault::touch(const std::string& model_id)
{
    bool changed = false;
    const auto now = QDateTime::currentSecsSinceEpoch();
    for (auto& art : artifacts)
    {
        if (art.id == model_id)
        {
            art.last_accessed = now;
            changed = true;
        }
    }
    if (changed)
        save();
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
        art.mmproj_filename = obj.value("mmproj_filename").toString().toStdString();
        art.mmproj_path = obj.value("mmproj_path").toString().toStdString();
        art.format = obj.value("format").toString().toStdString();
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
        obj.insert("mmproj_filename", QString::fromStdString(art.mmproj_filename));
        obj.insert("mmproj_path", QString::fromStdString(art.mmproj_path));
        obj.insert("format", QString::fromStdString(effective_format(art)));
        obj.insert("size_bytes", static_cast<double>(art.size_bytes));
        obj.insert("last_accessed", static_cast<double>(art.last_accessed));
        array.append(obj);
    }
    MP_FILEOPS.write_transactionally(index_path,
                                     QJsonDocument{array}.toJson(QJsonDocument::Indented));
}
