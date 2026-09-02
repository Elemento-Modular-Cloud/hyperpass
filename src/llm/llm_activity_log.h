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

#include <multipass/rpc/multipass.grpc.pb.h>

#include <chrono>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>

namespace multipass
{

class LlmActivityLog
{
public:
    using SubscriberId = std::uint64_t;
    using Callback = std::function<void(const ModelActivityEntry&)>;

    static constexpr std::size_t max_entries_per_model = 2000;

    void append(const std::string& model_id,
                const std::string& source,
                const std::string& level,
                const std::string& message);

    std::vector<ModelActivityEntry> snapshot(const std::string& model_id) const;

    SubscriberId subscribe(const std::string& model_id, Callback callback);
    void unsubscribe(SubscriberId id);

private:
    struct Subscription
    {
        std::string model_id;
        Callback callback;
    };

    static ModelActivityEntry make_entry(const std::string& source,
                                         const std::string& level,
                                         const std::string& message);

    mutable std::mutex mutex;
    std::unordered_map<std::string, std::deque<ModelActivityEntry>> buffers;
    std::unordered_map<SubscriberId, Subscription> subscribers;
    SubscriberId next_subscriber_id{1};
};

} // namespace multipass
