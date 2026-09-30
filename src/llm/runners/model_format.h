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

#include <string>

namespace multipass::llm
{

// On-disk / pull format for a vault artifact.
inline constexpr auto format_gguf = "gguf";
inline constexpr auto format_mlx = "mlx";
inline constexpr auto format_hf = "hf";
inline constexpr auto format_onnx = "onnx";

// Inference runner ids (LoadModelRequest.runtime / settings).
inline constexpr auto runner_llamacpp = "llamacpp";
inline constexpr auto runner_mlx = "mlx";
inline constexpr auto runner_vllm = "vllm";

inline std::string format_for_runner(const std::string& runner_id)
{
    if (runner_id == runner_mlx)
        return format_mlx;
    if (runner_id == runner_vllm)
        return format_hf;
    return format_gguf;
}

} // namespace multipass::llm
