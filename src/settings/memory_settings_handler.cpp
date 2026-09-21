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

#include <multipass/exceptions/settings_exceptions.h>
#include <multipass/settings/memory_settings_handler.h>

#include <algorithm>
#include <cassert>
#include <iterator>

namespace mp = multipass;

mp::MemorySettingsHandler::MemorySettingsHandler(SettingSpec::Set settings)
    : settings{convert(std::move(settings))}
{
}

QString mp::MemorySettingsHandler::get(const QString& key) const
{
    const auto& spec = get_setting(key);
    std::lock_guard<std::mutex> lock{mutex};
    const auto it = values.find(key);
    return it == values.end() ? spec.get_default() : it->second;
}

void mp::MemorySettingsHandler::set(const QString& key, const QString& val, UserMessages&)
{
    const auto interpreted = get_setting(key).interpret(val);
    std::lock_guard<std::mutex> lock{mutex};
    values[key] = interpreted;
}

std::set<QString> mp::MemorySettingsHandler::keys() const
{
    std::set<QString> ret{};
    std::transform(cbegin(settings),
                   cend(settings),
                   std::inserter(ret, begin(ret)),
                   [](const auto& elem) { return elem.first; });
    return ret;
}

const mp::SettingSpec& mp::MemorySettingsHandler::get_setting(const QString& key) const
{
    try
    {
        assert(settings.at(key) && "can't have null setting spec");
        return *settings.at(key);
    }
    catch (const std::out_of_range&)
    {
        throw UnrecognizedSettingException{key};
    }
}

auto mp::MemorySettingsHandler::convert(SettingSpec::Set settings) -> SettingMap
{
    SettingMap ret;
    while (!settings.empty())
    {
        auto it = settings.begin();
        assert(*it && "can't have null setting spec");
        auto key = (*it)->get_key();
        ret.emplace(std::move(key), std::move(settings.extract(it).value()));
    }
    return ret;
}
