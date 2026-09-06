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

#include "llama_server_process_spec.h"

namespace mp = multipass;

mp::LlamaServerProcessSpec::LlamaServerProcessSpec(QString program,
                                                   QString model_path,
                                                   QString openai_id,
                                                   int port,
                                                   int ctx_size,
                                                   int n_gpu_layers,
                                                   int max_tokens,
                                                   QString library_dir)
    : program_{std::move(program)},
      model_path{std::move(model_path)},
      openai_id{std::move(openai_id)},
      port{port},
      ctx_size{ctx_size},
      n_gpu_layers{n_gpu_layers},
      max_tokens{max_tokens},
      library_dir{std::move(library_dir)}
{
}

QString mp::LlamaServerProcessSpec::program() const
{
    return program_;
}

QStringList mp::LlamaServerProcessSpec::arguments() const
{
    QStringList args{"-m",
                     model_path,
                     "--host",
                     "127.0.0.1",
                     "--port",
                     QString::number(port),
                     "--ctx-size",
                     QString::number(ctx_size),
                     "--alias",
                     openai_id,
                     "--n-gpu-layers",
                     QString::number(n_gpu_layers)};
    if (max_tokens > 0)
        args << "--n-predict" << QString::number(max_tokens);
    return args;
}

QProcessEnvironment mp::LlamaServerProcessSpec::environment() const
{
    auto env = ProcessSpec::environment();
    if (library_dir.isEmpty())
        return env;

#ifdef Q_OS_MACOS
    constexpr auto key = "DYLD_LIBRARY_PATH";
    constexpr auto sep = ":";
#elif defined(Q_OS_WIN)
    constexpr auto key = "PATH";
    constexpr auto sep = ";";
#else
    constexpr auto key = "LD_LIBRARY_PATH";
    constexpr auto sep = ":";
#endif
    const auto existing = env.value(key);
    env.insert(key, existing.isEmpty() ? library_dir : library_dir + sep + existing);
    return env;
}

QString mp::LlamaServerProcessSpec::apparmor_profile() const
{
    return QString();
}

QString mp::LlamaServerProcessSpec::identifier() const
{
    return openai_id;
}
