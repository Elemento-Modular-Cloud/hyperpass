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

#include <memory>
#include <string>
#include <vector>

namespace multipass::llm
{

struct ResolvedRunner
{
    const InferenceRunner* runner{nullptr};
    RunnerDevice device{RunnerDevice::cpu};
};

class RunnerRegistry
{
public:
    RunnerRegistry();

    const InferenceRunner* get(const std::string& runner_id) const;
    const std::vector<const InferenceRunner*>& all() const
    {
        return ordered;
    }

    /// Honor explicit runtime from LoadModelRequest, else settings / auto.
    ResolvedRunner resolve(const std::string& runtime_request) const;
    /// Default from local.llm.backend setting (auto → platform llama device).
    ResolvedRunner select_default() const;

    RunnerDevice llama_device_for_platform() const;

private:
    std::vector<std::unique_ptr<InferenceRunner>> owners;
    std::vector<const InferenceRunner*> ordered;

    ResolvedRunner with_device(const InferenceRunner* runner) const;
};

} // namespace multipass::llm
