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

#include <multipass/path.h>
#include <multipass/rpc/multipass.grpc.pb.h>

#include <chrono>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace multipass
{

/**
 * Per-instance LLM activity buffer with optional jsonl persistence.
 *
 * When a log directory is set, every append is dual-written to
 * `<log_dir>/<instance_id>.jsonl` so lifecycle / process / gateway lines
 * survive daemon restarts. snapshot() / subscribe hydrate from disk when the
 * in-memory ring is empty.
 */
class LlmActivityLog
{
public:
    using SubscriberId = std::uint64_t;
    using Callback = std::function<void(const ModelActivityEntry&)>;

    static constexpr std::size_t max_entries_per_model = 2000;

    LlmActivityLog() = default;
    explicit LlmActivityLog(Path log_directory);

    void set_log_directory(Path log_directory);

    void append(const std::string& model_id,
                const std::string& source,
                const std::string& level,
                const std::string& message);

    /** Load disk history into memory when the ring is empty. */
    void hydrate(const std::string& model_id);

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

    QString file_for(const std::string& model_id) const;
    void persist_entry(const std::string& model_id, const ModelActivityEntry& entry) const;
    std::deque<ModelActivityEntry> load_from_file(const std::string& model_id) const;
    void hydrate_locked(const std::string& model_id) const;

    mutable std::mutex mutex;
    Path log_directory;
    mutable std::unordered_map<std::string, std::deque<ModelActivityEntry>> buffers;
    std::unordered_map<SubscriberId, Subscription> subscribers;
    SubscriberId next_subscriber_id{1};
};

} // namespace multipass
