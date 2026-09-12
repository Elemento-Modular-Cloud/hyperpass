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

#include <multipass/process/process_spec.h>

#include <QString>
#include <QStringList>

namespace multipass
{

struct LlamaServerOptions
{
    QString program;
    QString model_path;
    QString openai_id;
    int port{0};
    int ctx_size{4096};
    QString n_gpu_layers{"0"};
    int max_tokens{0};
    QString library_dir;
    QString mmproj_path;
    QString flash_attn;
    QString cache_type_k;
    QString cache_type_v;
    int threads{0};
    int threads_batch{0};
    int batch_size{0};
    int ubatch_size{0};
    int parallel{1};
    int cache_reuse{-1};
    bool fit{true};
    bool apply_fit{true};
    QString load_mode;
    bool cpu_moe{false};
    int n_cpu_moe{-1};
};

class LlamaServerProcessSpec : public ProcessSpec
{
public:
    explicit LlamaServerProcessSpec(LlamaServerOptions options);

    QString program() const override;
    QStringList arguments() const override;
    QProcessEnvironment environment() const override;
    logging::Level error_log_level() const override;
    QString apparmor_profile() const override;
    QString identifier() const override;

    const LlamaServerOptions& options() const
    {
        return options_;
    }

private:
    LlamaServerOptions options_;
};

} // namespace multipass
