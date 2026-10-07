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

#include "binary_locator.h"

#include "managed_tools.h"

#include <multipass/constants.h>

#include <QFileInfo>
#include <QProcessEnvironment>
#include <QStandardPaths>

namespace mp = multipass;

namespace
{
bool nvidia_present()
{
#ifndef Q_OS_MACOS
    return !QStandardPaths::findExecutable("nvidia-smi").isEmpty();
#else
    return false;
#endif
}
} // namespace

QString mp::llm::locate_binary(const char* env_var,
                               const QStringList& names,
                               const QString& managed_tools_dir,
                               const QString& managed_tool_name)
{
    if (env_var && *env_var)
    {
        const auto env = QProcessEnvironment::systemEnvironment().value(QString::fromUtf8(env_var));
        if (!env.isEmpty())
        {
            const QFileInfo info{env};
            if (info.exists() && info.isExecutable())
                return info.absoluteFilePath();
            return env;
        }
    }

    if (!managed_tools_dir.isEmpty() && !managed_tool_name.isEmpty())
    {
        const auto managed = find_in_managed(managed_tools_dir, managed_tool_name, names);
        if (!managed.isEmpty())
            return managed;
    }

    for (const auto& name : names)
    {
        const auto found = QStandardPaths::findExecutable(name);
        if (!found.isEmpty())
            return found;
    }
    return {};
}

QString mp::llm::locate_llama_server(const QString& managed_tools_dir)
{
    const QStringList names{QString::fromUtf8(tool_llama_server), QStringLiteral("llama_server")};

    if (const auto env = QProcessEnvironment::systemEnvironment().value(
            QString::fromUtf8(mp::llama_server_env_var));
        !env.isEmpty())
    {
        const QFileInfo info{env};
        if (info.exists() && info.isExecutable())
            return info.absoluteFilePath();
        return env;
    }

    if (nvidia_present() && !managed_tools_dir.isEmpty())
    {
        const auto cuda =
            find_in_managed(managed_tools_dir, QString::fromUtf8(tool_llama_server_cuda), names);
        if (!cuda.isEmpty())
            return cuda;
    }

    return locate_binary(mp::llama_server_env_var,
                         names,
                         managed_tools_dir,
                         QString::fromUtf8(tool_llama_server));
}
