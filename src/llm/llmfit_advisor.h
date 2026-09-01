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

#include <multipass/memory_size.h>
#include <multipass/rpc/multipass.grpc.pb.h>

#include <QString>

#include <chrono>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace multipass
{

struct ResolvedGguf
{
    std::string repo;
    std::string filename;
    std::string url;
};

class LlmfitAdvisor
{
public:
    std::vector<ModelSuggestion> recommend(MemorySize available_ram,
                                           int cpu_cores,
                                           const std::string& runtime,
                                           const std::string& use_case,
                                           const std::string& min_fit,
                                           int limit,
                                           bool unified_memory);

    std::vector<ModelSuggestion> browse(MemorySize available_ram,
                                        int cpu_cores,
                                        const std::string& runtime,
                                        const std::string& use_case,
                                        const std::string& min_fit,
                                        const std::string& query,
                                        int limit,
                                        int offset,
                                        bool include_too_tight,
                                        bool unified_memory);

    std::optional<ResolvedGguf> resolve(const std::string& model_id, const std::string& quant);

    QString binary_path() const;
    std::string missing_binary_hint() const;

private:
    struct CacheEntry
    {
        long long available_bytes{0};
        std::string runtime;
        std::string use_case;
        std::chrono::steady_clock::time_point at;
        std::vector<ModelSuggestion> models;
    };

    std::optional<CacheEntry> cache;
    mutable std::mutex mutex;
};

} // namespace multipass
