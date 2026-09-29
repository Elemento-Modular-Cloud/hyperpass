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

#include "provider_store.h"

#include <multipass/file_ops.h>
#include <multipass/format.h>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QUuid>

#include <stdexcept>

namespace mp = multipass;

namespace
{
constexpr auto store_filename = "providers.json";

std::string trim_slash(std::string url)
{
    while (!url.empty() && url.back() == '/')
        url.pop_back();
    return url;
}

std::vector<std::string> read_string_array(const QJsonObject& obj, const char* key)
{
    std::vector<std::string> out;
    const auto arr = obj.value(key);
    if (!arr.isArray())
        return out;
    for (const auto& item : arr.toArray())
    {
        const auto s = item.toString().trimmed().toStdString();
        if (!s.empty())
            out.push_back(s);
    }
    return out;
}

QJsonArray to_json_array(const std::vector<std::string>& values)
{
    QJsonArray arr;
    for (const auto& v : values)
        arr.append(QString::fromStdString(v));
    return arr;
}

bool glob_match(const std::string& pattern, const std::string& text)
{
    if (pattern.empty())
        return false;
    // Escape regex metacharacters except * and ?, then map those to regex.
    QString escaped;
    for (const QChar c : QString::fromStdString(pattern))
    {
        if (c == '*')
            escaped += ".*";
        else if (c == '?')
            escaped += '.';
        else
            escaped += QRegularExpression::escape(QString(c));
    }
    const QRegularExpression re(QStringLiteral("^%1$").arg(escaped),
                                QRegularExpression::DotMatchesEverythingOption |
                                    QRegularExpression::CaseInsensitiveOption);
    return re.match(QString::fromStdString(text)).hasMatch();
}
} // namespace

std::string mp::llm_provider_preset_base_url(const std::string& preset)
{
    if (preset == "openai")
        return "https://api.openai.com/v1";
    if (preset == "openrouter")
        return "https://openrouter.ai/api/v1";
    if (preset == "anthropic")
        return "https://api.anthropic.com/v1";
    return {};
}

std::string mp::llm_provider_key_prefix(const std::string& api_key)
{
    if (api_key.size() <= 8)
        return api_key;
    return api_key.substr(0, 8);
}

bool mp::llm_provider_id_matches(const std::string& model_id,
                                 const std::vector<std::string>& include,
                                 const std::vector<std::string>& exclude)
{
    for (const auto& pat : exclude)
    {
        if (glob_match(pat, model_id))
            return false;
    }
    if (include.empty())
        return true;
    for (const auto& pat : include)
    {
        if (glob_match(pat, model_id))
            return true;
    }
    return false;
}

mp::ProviderStore::ProviderStore(Path data_directory)
{
    QDir dir{data_directory};
    dir.mkpath("llm");
    store_path = dir.filePath(QStringLiteral("llm/%1").arg(store_filename));
    load();
}

mp::LlmProviderRecord mp::ProviderStore::create(const std::string& label,
                                                const std::string& preset,
                                                const std::string& base_url,
                                                const std::string& api_key,
                                                const std::vector<std::string>& include,
                                                const std::vector<std::string>& exclude)
{
    if (api_key.empty())
        throw std::runtime_error("provider API key is required");

    std::string resolved_preset = preset.empty() ? "custom" : preset;
    std::string resolved_url = trim_slash(base_url);
    if (resolved_url.empty())
        resolved_url = llm_provider_preset_base_url(resolved_preset);
    if (resolved_url.empty())
        throw std::runtime_error("provider base URL is required (use a preset or --base-url)");

    std::lock_guard lock{mutex};
    LlmProviderRecord rec;
    rec.id = QUuid::createUuid().toString(QUuid::WithoutBraces).toStdString();
    rec.label = label.empty() ? resolved_preset : label;
    rec.preset = resolved_preset;
    rec.base_url = resolved_url;
    rec.api_key = api_key;
    rec.key_prefix = llm_provider_key_prefix(api_key);
    rec.include = include;
    rec.exclude = exclude;
    rec.created_at = QDateTime::currentSecsSinceEpoch();
    providers.push_back(rec);
    save();
    return rec;
}

std::optional<mp::LlmProviderRecord> mp::ProviderStore::update(
    const std::string& id,
    const std::string& label,
    bool update_label,
    const std::string& base_url,
    bool update_base_url,
    const std::string& api_key,
    bool update_api_key,
    const std::vector<std::string>& include,
    bool update_include,
    const std::vector<std::string>& exclude,
    bool update_exclude)
{
    std::lock_guard lock{mutex};
    for (auto& rec : providers)
    {
        if (rec.id != id)
            continue;
        if (update_label)
            rec.label = label;
        if (update_base_url)
        {
            const auto trimmed = trim_slash(base_url);
            if (trimmed.empty())
                throw std::runtime_error("provider base URL cannot be empty");
            rec.base_url = trimmed;
            rec.preset = "custom";
        }
        if (update_api_key)
        {
            if (api_key.empty())
                throw std::runtime_error("provider API key cannot be empty");
            rec.api_key = api_key;
            rec.key_prefix = llm_provider_key_prefix(api_key);
        }
        if (update_include)
            rec.include = include;
        if (update_exclude)
            rec.exclude = exclude;
        save();
        return rec;
    }
    return std::nullopt;
}

std::vector<mp::LlmProviderRecord> mp::ProviderStore::list() const
{
    std::lock_guard lock{mutex};
    return providers;
}

std::optional<mp::LlmProviderRecord> mp::ProviderStore::get(const std::string& id) const
{
    std::lock_guard lock{mutex};
    for (const auto& rec : providers)
    {
        if (rec.id == id)
            return rec;
    }
    return std::nullopt;
}

bool mp::ProviderStore::remove(const std::string& id)
{
    std::lock_guard lock{mutex};
    const auto before = providers.size();
    std::erase_if(providers, [&](const auto& p) { return p.id == id; });
    if (providers.size() == before)
        return false;
    save();
    return true;
}

bool mp::ProviderStore::touch_refresh(const std::string& id)
{
    std::lock_guard lock{mutex};
    for (auto& rec : providers)
    {
        if (rec.id != id)
            continue;
        rec.last_refresh_at = QDateTime::currentSecsSinceEpoch();
        save();
        return true;
    }
    return false;
}

void mp::ProviderStore::load()
{
    providers.clear();
    QFile file{store_path};
    if (!file.exists())
        return;
    if (!file.open(QIODevice::ReadOnly))
        throw std::runtime_error(
            fmt::format("unable to read LLM provider store '{}'", store_path.toStdString()));

    const auto doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isArray())
        return;
    for (const auto& item : doc.array())
    {
        if (!item.isObject())
            continue;
        const auto obj = item.toObject();
        LlmProviderRecord rec;
        rec.id = obj.value("id").toString().toStdString();
        rec.label = obj.value("label").toString().toStdString();
        rec.preset = obj.value("preset").toString("custom").toStdString();
        rec.base_url = trim_slash(obj.value("base_url").toString().toStdString());
        rec.api_key = obj.value("api_key").toString().toStdString();
        rec.key_prefix = obj.value("key_prefix").toString().toStdString();
        if (rec.key_prefix.empty() && !rec.api_key.empty())
            rec.key_prefix = llm_provider_key_prefix(rec.api_key);
        rec.include = read_string_array(obj, "include");
        rec.exclude = read_string_array(obj, "exclude");
        rec.created_at = static_cast<long long>(obj.value("created_at").toDouble());
        rec.last_refresh_at = static_cast<long long>(obj.value("last_refresh_at").toDouble());
        if (!rec.id.empty() && !rec.base_url.empty() && !rec.api_key.empty())
            providers.push_back(std::move(rec));
    }
}

void mp::ProviderStore::save() const
{
    QJsonArray array;
    for (const auto& rec : providers)
    {
        QJsonObject obj;
        obj.insert("id", QString::fromStdString(rec.id));
        obj.insert("label", QString::fromStdString(rec.label));
        obj.insert("preset", QString::fromStdString(rec.preset));
        obj.insert("base_url", QString::fromStdString(rec.base_url));
        obj.insert("api_key", QString::fromStdString(rec.api_key));
        obj.insert("key_prefix", QString::fromStdString(rec.key_prefix));
        obj.insert("include", to_json_array(rec.include));
        obj.insert("exclude", to_json_array(rec.exclude));
        obj.insert("created_at", static_cast<double>(rec.created_at));
        obj.insert("last_refresh_at", static_cast<double>(rec.last_refresh_at));
        array.append(obj);
    }
    MP_FILEOPS.write_transactionally(store_path,
                                     QJsonDocument{array}.toJson(QJsonDocument::Indented));
}
