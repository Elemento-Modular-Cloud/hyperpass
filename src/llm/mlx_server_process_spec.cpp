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

namespace mp = multipass;

mp::MlxServerProcessSpec::MlxServerProcessSpec(QString program, QString model_path, int port)
    : program_{std::move(program)}, model_path{std::move(model_path)}, port{port}
{
}

QString mp::MlxServerProcessSpec::program() const
{
    return program_;
}

QStringList mp::MlxServerProcessSpec::arguments() const
{
    // python -m mlx_lm.server --host 127.0.0.1 --port N --model path
    if (program_.endsWith("python") || program_.endsWith("python3") ||
        program_.contains("python3."))
    {
        return {"-m",
                "mlx_lm.server",
                "--host",
                "127.0.0.1",
                "--port",
                QString::number(port),
                "--model",
                model_path};
    }
    return {"--host", "127.0.0.1", "--port", QString::number(port), "--model", model_path};
}

QString mp::MlxServerProcessSpec::apparmor_profile() const
{
    return QString();
}

QString mp::MlxServerProcessSpec::identifier() const
{
    return QStringLiteral("mlx-%1").arg(port);
}
