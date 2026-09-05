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

#include "vm_registry.h"

#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/standard_paths.h>
#include <multipass/utils.h>

#include <boost/json.hpp>

#include <QDir>
#include <QFile>
#include <QSaveFile>

#include <stdexcept>

namespace mp = multipass;
namespace mpl = multipass::logging;
namespace json = boost::json;

namespace
{
constexpr auto category = "vm-registry";

json::object to_json(const mp::api::RegisteredVm& vm)
{
    json::object obj;
    obj["vm_uid"] = vm.vm_uid;
    obj["vm_name"] = vm.vm_name;
    obj["client_uid"] = vm.client_uid;
    obj["os_family"] = vm.os_family;
    obj["os_flavour"] = vm.os_flavour;
    obj["backend"] = vm.backend;
    if (!vm.req_json.empty())
    {
        try
        {
            obj["req_json"] = json::parse(vm.req_json);
        }
        catch (const std::exception&)
        {
            obj["req_json"] = vm.req_json;
        }
    }
    if (!vm.xml.empty())
        obj["xml"] = vm.xml;
    return obj;
}

mp::api::RegisteredVm from_json(const json::object& obj)
{
    mp::api::RegisteredVm vm;
    vm.vm_uid = std::string(obj.at("vm_uid").as_string());
    vm.vm_name = std::string(obj.at("vm_name").as_string());
    vm.client_uid = std::string(obj.at("client_uid").as_string());
    if (obj.contains("os_family") && obj.at("os_family").is_string())
        vm.os_family = std::string(obj.at("os_family").as_string());
    if (obj.contains("os_flavour") && obj.at("os_flavour").is_string())
        vm.os_flavour = std::string(obj.at("os_flavour").as_string());
    if (obj.contains("backend") && obj.at("backend").is_string())
        vm.backend = std::string(obj.at("backend").as_string());
    if (obj.contains("req_json"))
    {
        if (obj.at("req_json").is_object() || obj.at("req_json").is_array())
            vm.req_json = json::serialize(obj.at("req_json"));
        else if (obj.at("req_json").is_string())
            vm.req_json = std::string(obj.at("req_json").as_string());
    }
    if (obj.contains("xml") && obj.at("xml").is_string())
        vm.xml = std::string(obj.at("xml").as_string());
    return vm;
}
} // namespace

std::string mp::api::VmRegistry::default_path()
{
    const auto data =
        MP_STDPATHS.writableLocation(StandardPaths::GenericDataLocation);
    const QDir dir{data + "/elp-api"};
    if (!dir.exists())
        QDir().mkpath(dir.path());
    return dir.filePath("vm_registry.json").toStdString();
}

mp::api::VmRegistry::VmRegistry(std::string path) : path{std::move(path)}
{
    std::lock_guard lock{mutex};
    load_unlocked();
}

void mp::api::VmRegistry::load_unlocked()
{
    by_uid.clear();
    QFile file{QString::fromStdString(path)};
    if (!file.exists())
        return;

    if (!file.open(QIODevice::ReadOnly))
    {
        mpl::log_message(mpl::Level::warning,
                         category,
                         fmt::format("failed to open registry {}: {}", path, file.errorString()));
        return;
    }

    const auto bytes = file.readAll().toStdString();
    if (bytes.empty())
        return;

    try
    {
        const auto parsed = json::parse(bytes);
        if (!parsed.is_object() || !parsed.as_object().contains("vms"))
            return;
        for (const auto& item : parsed.as_object().at("vms").as_array())
        {
            auto vm = from_json(item.as_object());
            by_uid.emplace(vm.vm_uid, std::move(vm));
        }
    }
    catch (const std::exception& e)
    {
        mpl::log_message(mpl::Level::warning,
                         category,
                         fmt::format("failed to parse registry {}: {}", path, e.what()));
    }
}

void mp::api::VmRegistry::save_unlocked() const
{
    json::object root;
    json::array vms;
    for (const auto& [_, vm] : by_uid)
        vms.push_back(to_json(vm));
    root["vms"] = std::move(vms);

    QSaveFile file{QString::fromStdString(path)};
    if (!file.open(QIODevice::WriteOnly))
        throw std::runtime_error(
            fmt::format("failed to write registry {}: {}", path, file.errorString()));

    const auto body = json::serialize(root);
    if (file.write(body.data(), static_cast<qint64>(body.size())) < 0)
        throw std::runtime_error(
            fmt::format("failed to write registry {}: {}", path, file.errorString()));
    if (!file.commit())
        throw std::runtime_error(
            fmt::format("failed to commit registry {}: {}", path, file.errorString()));
}

mp::api::RegisteredVm mp::api::VmRegistry::upsert(RegisteredVm record)
{
    std::lock_guard lock{mutex};
    by_uid[record.vm_uid] = record;
    save_unlocked();
    return record;
}

bool mp::api::VmRegistry::remove(const std::string& vm_uid)
{
    std::lock_guard lock{mutex};
    const auto erased = by_uid.erase(vm_uid) > 0;
    if (erased)
        save_unlocked();
    return erased;
}

std::optional<mp::api::RegisteredVm> mp::api::VmRegistry::find_by_uid(
    const std::string& vm_uid) const
{
    std::lock_guard lock{mutex};
    const auto it = by_uid.find(vm_uid);
    if (it == by_uid.end())
        return std::nullopt;
    return it->second;
}

std::optional<mp::api::RegisteredVm> mp::api::VmRegistry::find_by_name(
    const std::string& vm_name) const
{
    std::lock_guard lock{mutex};
    for (const auto& [_, vm] : by_uid)
    {
        if (vm.vm_name == vm_name)
            return vm;
    }
    return std::nullopt;
}

std::vector<mp::api::RegisteredVm> mp::api::VmRegistry::list_for_client(
    const std::string& client_uid) const
{
    std::lock_guard lock{mutex};
    std::vector<RegisteredVm> out;
    for (const auto& [_, vm] : by_uid)
    {
        if (vm.client_uid == client_uid)
            out.push_back(vm);
    }
    return out;
}

std::vector<mp::api::RegisteredVm> mp::api::VmRegistry::all() const
{
    std::lock_guard lock{mutex};
    std::vector<RegisteredVm> out;
    out.reserve(by_uid.size());
    for (const auto& [_, vm] : by_uid)
        out.push_back(vm);
    return out;
}
