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

#include <chrono>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>

namespace multipass::api
{

enum class OperationState
{
    pending,
    running,
    succeeded,
    failed
};

struct Operation
{
    std::string id;
    std::string kind;
    OperationState state{OperationState::pending};
    std::string message;
    std::string error;
    std::chrono::system_clock::time_point created_at;
    std::chrono::system_clock::time_point updated_at;
};

/**
 * In-process tracker for long-running daemon operations (launch, etc.).
 * Handlers start an operation, return 202 + id, and update state from gRPC streams.
 */
class OperationTracker
{
public:
    std::string start(std::string kind, std::string message = {});
    std::optional<Operation> get(const std::string& id) const;
    bool update(const std::string& id, OperationState state, std::string message = {});
    bool fail(const std::string& id, std::string error);
    bool succeed(const std::string& id, std::string message = {});

private:
    mutable std::mutex mutex;
    std::unordered_map<std::string, Operation> operations;
    std::uint64_t next_id{1};
};

std::string operation_state_name(OperationState state);

} // namespace multipass::api
