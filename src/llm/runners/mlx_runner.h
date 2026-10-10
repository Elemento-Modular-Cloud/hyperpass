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

#include "inference_runner.h"

namespace multipass::llm
{

class MlxRunner : public InferenceRunner
{
public:
    std::string id() const override;
    std::string display_name() const override;
    std::vector<std::string> formats() const override;
    bool available_on_platform() const override;
    bool uses_gpu(RunnerDevice device) const override;
    std::string session_backend_name(RunnerDevice device) const override;
    long long estimate_claim_bytes(const RunnerLaunchContext& ctx) const override;
    std::unique_ptr<Process> start(const RunnerLaunchContext& ctx) const override;
};

} // namespace multipass::llm
