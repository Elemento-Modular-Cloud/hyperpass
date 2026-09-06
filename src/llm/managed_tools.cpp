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

#include "managed_tools.h"

#include <QDir>
#include <QFileInfo>

namespace mp = multipass;

namespace
{
QString pinned_version_for(const QString& tool_name)
{
    if (tool_name == mp::llm::tool_llmfit)
        return QString::fromUtf8(mp::llm::pinned_llmfit_version);
    if (tool_name == mp::llm::tool_llama_server)
        return QString::fromUtf8(mp::llm::pinned_llama_build);
    return {};
}

QString find_named_executable(const QDir& dir, const QStringList& names)
{
    for (const auto& name : names)
    {
        const QFileInfo direct{dir.filePath(name)};
        if (direct.exists() && direct.isFile() && direct.isExecutable())
            return direct.absoluteFilePath();
#ifdef Q_OS_WIN
        const QFileInfo exe{dir.filePath(name + ".exe")};
        if (exe.exists() && exe.isFile())
            return exe.absoluteFilePath();
#endif
    }

    const auto entries = dir.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot);
    for (const auto& entry : entries)
    {
        if (entry.isDir())
        {
            const auto nested = find_named_executable(QDir{entry.absoluteFilePath()}, names);
            if (!nested.isEmpty())
                return nested;
        }
        else if (entry.isFile())
        {
            for (const auto& name : names)
            {
                if (entry.fileName() == name
#ifdef Q_OS_WIN
                    || entry.fileName() == name + ".exe"
#endif
                )
                {
                    if (entry.isExecutable()
#ifdef Q_OS_WIN
                        || entry.suffix().compare("exe", Qt::CaseInsensitive) == 0
#endif
                    )
                        return entry.absoluteFilePath();
                }
            }
        }
    }
    return {};
}
} // namespace

QString mp::llm::managed_tools_root(const Path& data_directory)
{
    return QDir{data_directory}.filePath("llm/tools");
}

QString mp::llm::managed_version_dir(const QString& tools_root, const QString& tool_name)
{
    const auto version = pinned_version_for(tool_name);
    if (tools_root.isEmpty() || tool_name.isEmpty() || version.isEmpty())
        return {};
    return QDir{tools_root}.filePath(tool_name + "/" + version);
}

QString mp::llm::find_in_managed(const QString& tools_root,
                                 const QString& tool_name,
                                 const QStringList& names)
{
    const auto version_dir = managed_version_dir(tools_root, tool_name);
    if (version_dir.isEmpty())
        return {};
    QDir dir{version_dir};
    if (!dir.exists())
        return {};
    return find_named_executable(dir, names);
}

bool mp::llm::is_under_managed_tools(const QString& binary_path, const QString& tools_root)
{
    if (binary_path.isEmpty() || tools_root.isEmpty())
        return false;
    const QFileInfo binary{binary_path};
    const QFileInfo root{tools_root};
    const auto canon_binary = binary.absoluteFilePath();
    const auto canon_root = root.absoluteFilePath();
    return canon_binary.startsWith(canon_root + "/") || canon_binary.startsWith(canon_root + "\\");
}
