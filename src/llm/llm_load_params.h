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

#include "llama_server_process_spec.h"

#include <multipass/rpc/multipass.grpc.pb.h>

#include <QJsonObject>

#include <string>

namespace multipass
{

bool looks_like_moe_model(const std::string& model_id);

double kv_cache_byte_scale(const std::string& cache_type_k, const std::string& cache_type_v);

struct ResolvedLlmLoad
{
    int ctx_size{4096};
    int max_tokens{0};
    LlamaServerOptions llama;
    LlmLoadParams echoed;
};

ResolvedLlmLoad resolve_llm_load(const LoadModelRequest& request, bool gpu_available);

QJsonObject llm_load_params_to_json(const LlmLoadParams& params);
LlmLoadParams llm_load_params_from_json(const QJsonObject& obj);

void apply_resolved_to_options(LlamaServerOptions& options, const ResolvedLlmLoad& resolved);

} // namespace multipass
