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

#include "mlx_server_process_spec.h"

#include <QDir>
#include <QFileInfo>

namespace mp = multipass;

mp::MlxServerProcessSpec::MlxServerProcessSpec(MlxServerOptions options)
    : options_{std::move(options)}
{
    if (!options_.hf_cache_dir.isEmpty())
        QDir{}.mkpath(options_.hf_cache_dir);
}

QString mp::MlxServerProcessSpec::program() const
{
    return options_.program;
}

QStringList mp::MlxServerProcessSpec::arguments() const
{
    // python -m mlx_lm.server --host 127.0.0.1 --port N --model path
    const auto& program = options_.program;
    if (program.endsWith("python") || program.endsWith("python3") || program.endsWith("python.exe") ||
        program.contains("python3.") || QFileInfo{program}.fileName().startsWith("python"))
    {
        return {"-m",
                "mlx_lm.server",
                "--host",
                "127.0.0.1",
                "--port",
                QString::number(options_.port),
                "--model",
                options_.model_path,
                "--use-default-chat-template"};
    }
    return {"--host",
            "127.0.0.1",
            "--port",
            QString::number(options_.port),
            "--model",
            options_.model_path,
            "--use-default-chat-template"};
}

QProcessEnvironment mp::MlxServerProcessSpec::environment() const
{
    auto env = ProcessSpec::environment();
    // mlx_lm.server's GET /v1/models calls scan_cache_dir(); without a cache dir
    // huggingface_hub raises CacheNotFound and the request thread dies.
    if (!options_.hf_cache_dir.isEmpty())
    {
        env.insert("HF_HUB_CACHE", options_.hf_cache_dir);
        env.insert("HUGGINGFACE_HUB_CACHE", options_.hf_cache_dir);
    }
    if (!options_.hf_token.isEmpty())
        env.insert("HF_TOKEN", options_.hf_token);
    return env;
}

QString mp::MlxServerProcessSpec::apparmor_profile() const
{
    return QString();
}

QString mp::MlxServerProcessSpec::identifier() const
{
    return QStringLiteral("mlx-%1").arg(options_.port);
}
