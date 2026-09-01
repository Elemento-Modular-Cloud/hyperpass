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

#include <QFileInfo>
#include <QProcessEnvironment>
#include <QStandardPaths>

namespace mp = multipass;

QString mp::llm::locate_binary(const char* env_var, const QStringList& names)
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

    for (const auto& name : names)
    {
        const auto found = QStandardPaths::findExecutable(name);
        if (!found.isEmpty())
            return found;
    }
    return {};
}
