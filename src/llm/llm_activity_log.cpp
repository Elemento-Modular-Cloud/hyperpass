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

#include <multipass/logging/log.h>

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>

#include <optional>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto log_category = "llm-activity";
constexpr qint64 max_tail_bytes = 1024 * 1024; // 1 MiB

QString sanitize_id(const std::string& model_id)
{
    QString id = QString::fromStdString(model_id);
    id.replace('/', '_');
    id.replace('\\', '_');
    id.replace(':', '_');
    return id;
}

QByteArray entry_to_jsonl(const mp::ModelActivityEntry& entry)
{
    QJsonObject obj;
    obj.insert("timestamp_ms", static_cast<qint64>(entry.timestamp_ms()));
    obj.insert("source", QString::fromStdString(entry.source()));
    obj.insert("level", QString::fromStdString(entry.level()));
    obj.insert("message", QString::fromStdString(entry.message()));
    return QJsonDocument{obj}.toJson(QJsonDocument::Compact);
}

std::optional<mp::ModelActivityEntry> entry_from_jsonl(const QByteArray& line)
{
    const auto trimmed = line.trimmed();
    if (trimmed.isEmpty())
        return std::nullopt;

    QJsonParseError error{};
    const auto doc = QJsonDocument::fromJson(trimmed, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject())
        return std::nullopt;

    const auto obj = doc.object();
    mp::ModelActivityEntry entry;
    entry.set_timestamp_ms(obj.value("timestamp_ms").toVariant().toLongLong());
    entry.set_source(obj.value("source").toString().toStdString());
    entry.set_level(obj.value("level").toString().toStdString());
    entry.set_message(obj.value("message").toString().toStdString());
    if (entry.message().empty())
        return std::nullopt;
    return entry;
}
} // namespace

mp::LlmActivityLog::LlmActivityLog(Path log_directory_arg)
{
    set_log_directory(std::move(log_directory_arg));
}

void mp::LlmActivityLog::set_log_directory(Path log_directory_arg)
{
    std::lock_guard lock{mutex};
    log_directory = std::move(log_directory_arg);
    if (log_directory.isEmpty())
        return;

    QDir dir{log_directory};
    if (!dir.exists() && !dir.mkpath("."))
    {
        mpl::warn(log_category,
                  "Could not create LLM activity log dir '{}'",
                  log_directory.toStdString());
        log_directory.clear();
    }
}

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

QString mp::LlmActivityLog::file_for(const std::string& model_id) const
{
    if (log_directory.isEmpty() || model_id.empty())
        return {};
    return QDir{log_directory}.filePath(sanitize_id(model_id) + ".jsonl");
}

void mp::LlmActivityLog::persist_entry(const std::string& model_id,
                                       const ModelActivityEntry& entry) const
{
    const auto path = file_for(model_id);
    if (path.isEmpty())
        return;

    QFile file{path};
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
    {
        mpl::warn(log_category,
                  "Could not append LLM activity log '{}'",
                  path.toStdString());
        return;
    }
    file.write(entry_to_jsonl(entry));
    file.write("\n");
}

std::deque<mp::ModelActivityEntry> mp::LlmActivityLog::load_from_file(
    const std::string& model_id) const
{
    const auto path = file_for(model_id);
    if (path.isEmpty())
        return {};

    QFile file{path};
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};

    const auto size = file.size();
    if (size > max_tail_bytes)
    {
        file.seek(size - max_tail_bytes);
        // Drop possibly partial first line after mid-file seek.
        file.readLine();
    }

    std::deque<ModelActivityEntry> entries;
    while (!file.atEnd())
    {
        if (auto parsed = entry_from_jsonl(file.readLine()))
        {
            entries.push_back(std::move(*parsed));
            while (entries.size() > max_entries_per_model)
                entries.pop_front();
        }
    }
    return entries;
}

void mp::LlmActivityLog::hydrate_locked(const std::string& model_id) const
{
    if (model_id.empty())
        return;
    auto& buffer = buffers[model_id];
    if (!buffer.empty())
        return;

    auto from_disk = load_from_file(model_id);
    if (!from_disk.empty())
        buffer = std::move(from_disk);
}

void mp::LlmActivityLog::hydrate(const std::string& model_id)
{
    std::lock_guard lock{mutex};
    hydrate_locked(model_id);
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
        hydrate_locked(model_id);
        auto& buffer = buffers[model_id];
        buffer.push_back(entry);
        while (buffer.size() > max_entries_per_model)
            buffer.pop_front();

        persist_entry(model_id, entry);

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
    hydrate_locked(model_id);
    const auto it = buffers.find(model_id);
    if (it == buffers.end())
        return {};
    return {it->second.begin(), it->second.end()};
}

mp::LlmActivityLog::SubscriberId mp::LlmActivityLog::subscribe(const std::string& model_id,
                                                               Callback callback)
{
    std::lock_guard lock{mutex};
    hydrate_locked(model_id);
    const auto id = next_subscriber_id++;
    subscribers[id] = Subscription{model_id, std::move(callback)};
    return id;
}

void mp::LlmActivityLog::unsubscribe(SubscriberId id)
{
    std::lock_guard lock{mutex};
    subscribers.erase(id);
}
