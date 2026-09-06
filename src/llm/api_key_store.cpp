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

#include "api_key_store.h"

#include <multipass/file_ops.h>
#include <multipass/format.h>
#include <multipass/utils.h>

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUuid>

#include <stdexcept>

namespace mp = multipass;

namespace
{
constexpr auto store_filename = "api_keys.json";

QString to_hex(const QByteArray& bytes)
{
    return QString::fromLatin1(bytes.toHex());
}

std::string sha256_hex(const std::string& secret)
{
    const auto hash =
        QCryptographicHash::hash(QByteArray::fromStdString(secret), QCryptographicHash::Sha256);
    return to_hex(hash).toStdString();
}

std::string random_hex(size_t nbytes)
{
    const auto bytes = MP_UTILS.random_bytes(nbytes);
    QByteArray raw{reinterpret_cast<const char*>(bytes.data()), static_cast<int>(bytes.size())};
    return to_hex(raw).toStdString();
}

std::vector<std::string> unique_ids(const std::vector<std::string>& ids)
{
    std::vector<std::string> out;
    out.reserve(ids.size());
    for (const auto& id : ids)
    {
        if (id.empty())
            continue;
        if (std::find(out.begin(), out.end(), id) == out.end())
            out.push_back(id);
    }
    return out;
}

std::vector<std::string> read_instance_ids(const QJsonObject& obj)
{
    std::vector<std::string> ids;
    const auto arr = obj.value("instance_ids");
    if (arr.isArray())
    {
        for (const auto& item : arr.toArray())
        {
            const auto id = item.toString().toStdString();
            if (!id.empty())
                ids.push_back(id);
        }
        return unique_ids(ids);
    }
    const auto legacy = obj.value("instance_id").toString().toStdString();
    if (!legacy.empty())
        ids.push_back(legacy);
    return ids;
}
} // namespace

mp::ApiKeyStore::ApiKeyStore(Path data_directory)
{
    QDir dir{data_directory};
    dir.mkpath("llm");
    store_path = dir.filePath(QStringLiteral("llm/%1").arg(store_filename));
    load();
}

mp::ApiKeyStore::CreatedKey mp::ApiKeyStore::create(const std::string& label,
                                                    const std::vector<std::string>& instance_ids)
{
    std::lock_guard lock{mutex};
    CreatedKey created;
    created.secret = "sk-elp-" + random_hex(24);
    created.record.id = QUuid::createUuid().toString(QUuid::WithoutBraces).toStdString();
    created.record.prefix = created.secret.substr(0, 11);
    created.record.label = label;
    created.record.sha256_hex = sha256_hex(created.secret);
    created.record.created_at = QDateTime::currentSecsSinceEpoch();
    created.record.instance_ids = unique_ids(instance_ids);
    keys.push_back(created.record);
    save();
    return created;
}

std::optional<mp::ApiKeyRecord> mp::ApiKeyStore::update(const std::string& id,
                                                        const std::string& label,
                                                        const std::vector<std::string>& instance_ids,
                                                        bool update_label,
                                                        bool update_instance_ids)
{
    std::lock_guard lock{mutex};
    for (auto& key : keys)
    {
        if (key.id != id)
            continue;
        if (update_label)
            key.label = label;
        if (update_instance_ids)
            key.instance_ids = unique_ids(instance_ids);
        save();
        return key;
    }
    return std::nullopt;
}

std::vector<mp::ApiKeyRecord> mp::ApiKeyStore::list() const
{
    std::lock_guard lock{mutex};
    return keys;
}

bool mp::ApiKeyStore::revoke_by_id(const std::string& id)
{
    std::lock_guard lock{mutex};
    const auto before = keys.size();
    std::erase_if(keys, [&](const auto& k) { return k.id == id; });
    if (keys.size() == before)
        return false;
    save();
    return true;
}

bool mp::ApiKeyStore::revoke_by_prefix(const std::string& prefix)
{
    std::lock_guard lock{mutex};
    const auto before = keys.size();
    std::erase_if(keys, [&](const auto& k) { return k.prefix == prefix || k.id == prefix; });
    if (keys.size() == before)
        return false;
    save();
    return true;
}

void mp::ApiKeyStore::revoke_for_instance(const std::string& instance_id)
{
    if (instance_id.empty())
        return;
    std::lock_guard lock{mutex};
    bool changed = false;
    std::vector<ApiKeyRecord> next;
    next.reserve(keys.size());
    for (auto& key : keys)
    {
        if (key.instance_ids.empty())
        {
            // Global key — keep.
            next.push_back(std::move(key));
            continue;
        }
        const auto before = key.instance_ids.size();
        std::erase(key.instance_ids, instance_id);
        if (key.instance_ids.size() != before)
            changed = true;
        if (key.instance_ids.empty())
        {
            // Scoped key with no remaining bindings — revoke.
            changed = true;
            continue;
        }
        next.push_back(std::move(key));
    }
    if (changed)
    {
        keys = std::move(next);
        save();
    }
}

std::optional<mp::ApiKeyRecord> mp::ApiKeyStore::verify(const std::string& secret) const
{
    std::lock_guard lock{mutex};
    if (secret.rfind("sk-elp-", 0) != 0)
        return std::nullopt;
    const auto digest = sha256_hex(secret);
    for (const auto& key : keys)
    {
        if (key.sha256_hex == digest)
            return key;
    }
    return std::nullopt;
}

void mp::ApiKeyStore::load()
{
    keys.clear();
    QFile file{store_path};
    if (!file.exists())
        return;
    if (!file.open(QIODevice::ReadOnly))
        throw std::runtime_error(
            fmt::format("unable to read API key store '{}'", store_path.toStdString()));

    const auto doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isArray())
        return;
    for (const auto& item : doc.array())
    {
        if (!item.isObject())
            continue;
        const auto obj = item.toObject();
        ApiKeyRecord rec;
        rec.id = obj.value("id").toString().toStdString();
        rec.prefix = obj.value("prefix").toString().toStdString();
        rec.label = obj.value("label").toString().toStdString();
        rec.sha256_hex = obj.value("sha256").toString().toStdString();
        rec.created_at = static_cast<long long>(obj.value("created_at").toDouble());
        rec.instance_ids = read_instance_ids(obj);
        if (!rec.id.empty() && !rec.sha256_hex.empty())
            keys.push_back(std::move(rec));
    }
}

void mp::ApiKeyStore::save() const
{
    QJsonArray array;
    for (const auto& key : keys)
    {
        QJsonObject obj;
        obj.insert("id", QString::fromStdString(key.id));
        obj.insert("prefix", QString::fromStdString(key.prefix));
        obj.insert("label", QString::fromStdString(key.label));
        obj.insert("sha256", QString::fromStdString(key.sha256_hex));
        obj.insert("created_at", static_cast<double>(key.created_at));
        if (!key.instance_ids.empty())
        {
            QJsonArray ids;
            for (const auto& id : key.instance_ids)
                ids.append(QString::fromStdString(id));
            obj.insert("instance_ids", ids);
            obj.insert("instance_id", QString::fromStdString(key.instance_ids.front()));
        }
        array.append(obj);
    }
    MP_FILEOPS.write_transactionally(store_path,
                                     QJsonDocument{array}.toJson(QJsonDocument::Indented));
}
