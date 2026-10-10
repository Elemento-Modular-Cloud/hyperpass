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

#include "model_format.h"

#include "../llm_load_params.h"
#include "../model_vault.h"

#include <multipass/path.h>
#include <multipass/process/process.h>

#include <memory>
#include <string>
#include <vector>

namespace multipass::llm
{

enum class RunnerDevice
{
    cpu,
    metal,
    cuda
};

struct RunnerLaunchContext
{
    ModelArtifact artifact;
    int port{0};
    std::string openai_id;
    ResolvedLlmLoad resolved;
    Path data_directory;
    RunnerDevice device{RunnerDevice::cpu};
    /// Optional Hugging Face token (settings / HF_TOKEN) for hub downloads.
    std::string hf_token;
};

class InferenceRunner
{
public:
    virtual ~InferenceRunner() = default;

    virtual std::string id() const = 0;
    virtual std::string display_name() const = 0;
    virtual std::vector<std::string> formats() const = 0;
    virtual bool openai_compat() const
    {
        return true;
    }
    virtual bool available_on_platform() const = 0;
    virtual bool uses_gpu(RunnerDevice device) const = 0;
    /// Persisted LoadedSession.backend string (may include device suffix).
    virtual std::string session_backend_name(RunnerDevice device) const = 0;
    /// Host-pool admit estimate for this launch (bytes). Backend-specific.
    virtual long long estimate_claim_bytes(const RunnerLaunchContext& ctx) const = 0;
    virtual std::unique_ptr<Process> start(const RunnerLaunchContext& ctx) const = 0;
};

} // namespace multipass::llm
