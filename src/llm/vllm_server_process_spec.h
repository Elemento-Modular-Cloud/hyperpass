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

struct VllmServerOptions
{
    QString program;
    QString launch_mode; // "cli" (vllm serve) | "python" (-m vllm.entrypoints.openai.api_server)
    QString model;
    int port{0};
    QString openai_id;
    QString dtype;
    double gpu_memory_utilization{0};
    int max_model_len{0};
    QString hf_cache_dir;
    QString hf_token;
};

class VllmServerProcessSpec : public ProcessSpec
{
public:
    explicit VllmServerProcessSpec(VllmServerOptions options);

    QString program() const override;
    QStringList arguments() const override;
    QProcessEnvironment environment() const override;
    QString apparmor_profile() const override;
    QString identifier() const override;
    bool isolate_process_group() const override
    {
        return true;
    }

private:
    VllmServerOptions options_;
};

} // namespace multipass
