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
namespace mpl = multipass::logging;

mp::LlamaServerProcessSpec::LlamaServerProcessSpec(LlamaServerOptions options)
    : options_{std::move(options)}
{
}

QString mp::LlamaServerProcessSpec::program() const
{
    return options_.program;
}

QStringList mp::LlamaServerProcessSpec::arguments() const
{
    const auto& o = options_;
    QStringList args{"-m",
                     o.model_path,
                     "--host",
                     "127.0.0.1",
                     "--port",
                     QString::number(o.port),
                     "--ctx-size",
                     QString::number(o.ctx_size),
                     "--alias",
                     o.openai_id,
                     "--n-gpu-layers",
                     o.n_gpu_layers,
                     "--parallel",
                     QString::number(o.parallel > 0 ? o.parallel : 1)};
    if (!o.mmproj_path.isEmpty())
        args << "--mmproj" << o.mmproj_path;
    if (o.max_tokens > 0)
        args << "--n-predict" << QString::number(o.max_tokens);
    if (o.threads_batch > 0)
        args << "--threads-batch" << QString::number(o.threads_batch);
    return args;
}

mpl::Level mp::LlamaServerProcessSpec::error_log_level() const
{
    // llama-server writes informational boot logs to stderr.
    return mpl::Level::debug;
}

QProcessEnvironment mp::LlamaServerProcessSpec::environment() const
{
    auto env = ProcessSpec::environment();
    const auto& o = options_;
    // Prefer env over CLI flags so older llama-server builds ignore unknown
    // options instead of refusing to start. b10819 honors these (llama.cpp#25655).
    env.insert("LLAMA_ARG_CORS_ORIGINS", "localhost");
    env.insert("LLAMA_ARG_WEBUI", "0");
    env.insert("LLAMA_ARG_UI", "0");
    if (!o.flash_attn.isEmpty())
        env.insert("LLAMA_ARG_FLASH_ATTN", o.flash_attn);
    if (!o.cache_type_k.isEmpty())
        env.insert("LLAMA_ARG_CACHE_TYPE_K", o.cache_type_k);
    if (!o.cache_type_v.isEmpty())
        env.insert("LLAMA_ARG_CACHE_TYPE_V", o.cache_type_v);
    if (o.cache_reuse >= 0)
        env.insert("LLAMA_ARG_CACHE_REUSE", QString::number(o.cache_reuse));
    if (o.apply_fit)
        env.insert("LLAMA_ARG_FIT", o.fit ? "on" : "off");
    if (!o.load_mode.isEmpty())
        env.insert("LLAMA_ARG_LOAD_MODE", o.load_mode);
    if (o.cpu_moe)
        env.insert("LLAMA_ARG_CPU_MOE", "1");
    if (o.n_cpu_moe >= 0)
        env.insert("LLAMA_ARG_N_CPU_MOE", QString::number(o.n_cpu_moe));
    if (o.threads > 0)
        env.insert("LLAMA_ARG_THREADS", QString::number(o.threads));
    if (o.batch_size > 0)
        env.insert("LLAMA_ARG_BATCH", QString::number(o.batch_size));
    if (o.ubatch_size > 0)
        env.insert("LLAMA_ARG_UBATCH", QString::number(o.ubatch_size));

    if (o.library_dir.isEmpty())
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
    env.insert(key, existing.isEmpty() ? o.library_dir : o.library_dir + sep + existing);
    return env;
}

QString mp::LlamaServerProcessSpec::apparmor_profile() const
{
    return QString();
}

QString mp::LlamaServerProcessSpec::identifier() const
{
    return options_.openai_id;
}
