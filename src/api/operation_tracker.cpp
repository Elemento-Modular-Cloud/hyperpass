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

#include "operation_tracker.h"

#include <multipass/format.h>

namespace mp = multipass;

std::string mp::api::operation_state_name(OperationState state)
{
    switch (state)
    {
    case OperationState::pending:
        return "pending";
    case OperationState::running:
        return "running";
    case OperationState::succeeded:
        return "succeeded";
    case OperationState::failed:
        return "failed";
    }
    return "unknown";
}

std::string mp::api::OperationTracker::start(std::string kind, std::string message)
{
    std::lock_guard lock{mutex};
    const auto id = fmt::format("op-{}", next_id++);
    const auto now = std::chrono::system_clock::now();
    Operation op;
    op.id = id;
    op.kind = std::move(kind);
    op.state = OperationState::pending;
    op.message = std::move(message);
    op.created_at = now;
    op.updated_at = now;
    operations.emplace(id, std::move(op));
    return id;
}

std::optional<mp::api::Operation> mp::api::OperationTracker::get(const std::string& id) const
{
    std::lock_guard lock{mutex};
    const auto it = operations.find(id);
    if (it == operations.end())
        return std::nullopt;
    return it->second;
}

bool mp::api::OperationTracker::update(const std::string& id,
                                       OperationState state,
                                       std::string message)
{
    std::lock_guard lock{mutex};
    const auto it = operations.find(id);
    if (it == operations.end())
        return false;
    it->second.state = state;
    if (!message.empty())
        it->second.message = std::move(message);
    it->second.updated_at = std::chrono::system_clock::now();
    return true;
}

bool mp::api::OperationTracker::fail(const std::string& id, std::string error)
{
    std::lock_guard lock{mutex};
    const auto it = operations.find(id);
    if (it == operations.end())
        return false;
    it->second.state = OperationState::failed;
    it->second.error = std::move(error);
    it->second.updated_at = std::chrono::system_clock::now();
    return true;
}

bool mp::api::OperationTracker::succeed(const std::string& id, std::string message)
{
    return update(id, OperationState::succeeded, std::move(message));
}
