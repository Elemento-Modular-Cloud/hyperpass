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

#include <QDir>
#include <QFileInfo>
#include <QRegularExpression>
#include <QString>
#include <QStringList>

namespace multipass
{

inline bool is_mmproj_gguf(const QString& name)
{
    const auto base = QFileInfo{name}.fileName();
    static const QRegularExpression sidecar_re{
        R"(mmproj|mm-proj|(^|[-_.])clip([-_.]|$))",
        QRegularExpression::CaseInsensitiveOption};
    return sidecar_re.match(base).hasMatch();
}

inline bool is_sharded_gguf_name(const QString& name)
{
    return QFileInfo{name}.fileName().contains("-of-", Qt::CaseInsensitive);
}

inline QString pick_mmproj_file(const QStringList& files)
{
    for (const auto& file : files)
    {
        if (!file.endsWith(".gguf", Qt::CaseInsensitive))
            continue;
        if (is_sharded_gguf_name(file))
            continue;
        if (is_mmproj_gguf(file))
            return file;
    }
    return {};
}

inline QString pick_gguf_file(const QStringList& files, const QString& quant)
{
    QStringList usable;
    for (const auto& file : files)
    {
        if (!file.endsWith(".gguf", Qt::CaseInsensitive))
            continue;
        if (is_sharded_gguf_name(file) || is_mmproj_gguf(file))
            continue;
        usable << file;
    }
    if (usable.isEmpty())
        return {};

    auto exact = [&](const QString& tag) -> QString {
        const auto needle = QString{"-%1.gguf"}.arg(tag);
        for (const auto& file : usable)
        {
            if (file.endsWith(needle, Qt::CaseInsensitive))
                return file;
        }
        return {};
    };

    if (!quant.isEmpty() && !quant.startsWith("mlx", Qt::CaseInsensitive))
    {
        if (auto hit = exact(quant); !hit.isEmpty())
            return hit;
    }
    for (const auto& pref : {"Q4_K_M", "Q5_K_M", "Q6_K", "Q4_K_S", "Q8_0", "Q4_0"})
    {
        if (auto hit = exact(pref); !hit.isEmpty())
            return hit;
    }
    return usable.first();
}

inline QString find_sibling_mmproj(const QString& model_path)
{
    const QFileInfo info{model_path};
    const auto dir = info.absoluteDir();
    for (const auto& name : dir.entryList(QStringList{"*.gguf", "*.GGUF"}, QDir::Files))
    {
        if (!is_mmproj_gguf(name))
            continue;
        const auto path = dir.filePath(name);
        if (QFileInfo{path}.canonicalFilePath() != info.canonicalFilePath())
            return path;
    }
    return {};
}

} // namespace multipass
