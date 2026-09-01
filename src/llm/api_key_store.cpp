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
} // namespace

mp::ApiKeyStore::ApiKeyStore(Path data_directory)
{
    QDir dir{data_directory};
    dir.mkpath("llm");
    store_path = dir.filePath(QStringLiteral("llm/%1").arg(store_filename));
    load();
}

mp::ApiKeyStore::CreatedKey mp::ApiKeyStore::create(const std::string& label)
{
    CreatedKey created;
    created.secret = "sk-hp-" + random_hex(24);
    created.record.id = QUuid::createUuid().toString(QUuid::WithoutBraces).toStdString();
    created.record.prefix = created.secret.substr(0, 11);
    created.record.label = label;
    created.record.sha256_hex = sha256_hex(created.secret);
    created.record.created_at = QDateTime::currentSecsSinceEpoch();
    keys.push_back(created.record);
    save();
    return created;
}

std::vector<mp::ApiKeyRecord> mp::ApiKeyStore::list() const
{
    return keys;
}

bool mp::ApiKeyStore::revoke_by_id(const std::string& id)
{
    const auto before = keys.size();
    std::erase_if(keys, [&](const auto& k) { return k.id == id; });
    if (keys.size() == before)
        return false;
    save();
    return true;
}

bool mp::ApiKeyStore::revoke_by_prefix(const std::string& prefix)
{
    const auto before = keys.size();
    std::erase_if(keys, [&](const auto& k) { return k.prefix == prefix || k.id == prefix; });
    if (keys.size() == before)
        return false;
    save();
    return true;
}

std::optional<mp::ApiKeyRecord> mp::ApiKeyStore::verify(const std::string& secret) const
{
    if (secret.rfind("sk-hp-", 0) != 0)
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
        array.append(obj);
    }
    MP_FILEOPS.write_transactionally(store_path,
                                     QJsonDocument{array}.toJson(QJsonDocument::Indented));
}
