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

#include "llm_activity_log.h"

#include <vector>

namespace mp = multipass;

mp::ModelActivityEntry mp::LlmActivityLog::make_entry(const std::string& source,
                                                      const std::string& level,
                                                      const std::string& message)
{
    mp::ModelActivityEntry entry;
    const auto now = std::chrono::system_clock::now();
    entry.set_timestamp_ms(
        std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count());
    entry.set_source(source);
    entry.set_level(level);
    entry.set_message(message);
    return entry;
}

void mp::LlmActivityLog::append(const std::string& model_id,
                                const std::string& source,
                                const std::string& level,
                                const std::string& message)
{
    if (model_id.empty() || message.empty())
        return;

    const auto entry = make_entry(source, level, message);
    std::vector<Callback> callbacks;
    {
        std::lock_guard lock{mutex};
        auto& buffer = buffers[model_id];
        buffer.push_back(entry);
        while (buffer.size() > max_entries_per_model)
            buffer.pop_front();

        for (const auto& [_, subscription] : subscribers)
        {
            if (subscription.model_id == model_id)
                callbacks.push_back(subscription.callback);
        }
    }

    for (const auto& callback : callbacks)
        callback(entry);
}

std::vector<mp::ModelActivityEntry> mp::LlmActivityLog::snapshot(const std::string& model_id) const
{
    std::lock_guard lock{mutex};
    const auto it = buffers.find(model_id);
    if (it == buffers.end())
        return {};
    return {it->second.begin(), it->second.end()};
}

mp::LlmActivityLog::SubscriberId mp::LlmActivityLog::subscribe(const std::string& model_id,
                                                               Callback callback)
{
    std::lock_guard lock{mutex};
    const auto id = next_subscriber_id++;
    subscribers[id] = Subscription{model_id, std::move(callback)};
    return id;
}

void mp::LlmActivityLog::unsubscribe(SubscriberId id)
{
    std::lock_guard lock{mutex};
    subscribers.erase(id);
}
