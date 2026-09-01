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

class LlamaServerProcessSpec : public ProcessSpec
{
public:
    LlamaServerProcessSpec(QString program,
                           QString model_path,
                           QString openai_id,
                           int port,
                           int ctx_size,
                           int n_gpu_layers);

    QString program() const override;
    QStringList arguments() const override;
    QString apparmor_profile() const override;
    QString identifier() const override;

private:
    QString program_;
    QString model_path;
    QString openai_id;
    int port;
    int ctx_size;
    int n_gpu_layers;
};

} // namespace multipass
