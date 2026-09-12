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

#include <multipass/constants.h>
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
    obj["username"] = vm.username;
    obj["region"] = vm.region;
    obj["template_id"] = vm.template_id;
    obj["service_id"] = vm.service_id;
    obj["source"] = mp::api::normalize_vm_source(vm.source);
    if (!vm.spec_json.empty())
    {
        try
        {
            obj["spec"] = json::parse(vm.spec_json);
        }
        catch (const std::exception&)
        {
            obj["spec_json"] = vm.spec_json;
        }
    }
    return obj;
}

mp::api::RegisteredVm from_json(const json::object& obj)
{
    mp::api::RegisteredVm vm;
    if (!obj.contains("vm_uid") || !obj.at("vm_uid").is_string())
        throw std::runtime_error("missing vm_uid");
    if (!obj.contains("vm_name") || !obj.at("vm_name").is_string())
        throw std::runtime_error("missing vm_name");
    vm.vm_uid = std::string(obj.at("vm_uid").as_string());
    vm.vm_name = std::string(obj.at("vm_name").as_string());
    if (obj.contains("username") && obj.at("username").is_string())
        vm.username = std::string(obj.at("username").as_string());
    if (obj.contains("region") && obj.at("region").is_string())
        vm.region = std::string(obj.at("region").as_string());
    if (obj.contains("template_id") && obj.at("template_id").is_string())
        vm.template_id = std::string(obj.at("template_id").as_string());
    if (obj.contains("service_id") && obj.at("service_id").is_string())
        vm.service_id = std::string(obj.at("service_id").as_string());
    if (obj.contains("source") && obj.at("source").is_string())
        vm.source = mp::api::normalize_vm_source(std::string(obj.at("source").as_string()));
    else
        vm.source = mp::instance_source_elp;
    if (obj.contains("spec") && (obj.at("spec").is_object() || obj.at("spec").is_array()))
        vm.spec_json = json::serialize(obj.at("spec"));
    else if (obj.contains("spec_json") && obj.at("spec_json").is_string())
        vm.spec_json = std::string(obj.at("spec_json").as_string());
    return vm;
}
} // namespace

std::string mp::api::normalize_vm_source(std::string_view source)
{
    if (source == mp::instance_source_multipass)
        return std::string{mp::instance_source_multipass};
    return std::string{mp::instance_source_elp};
}

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
            if (!item.is_object())
                continue;
            try
            {
                auto vm = from_json(item.as_object());
                by_uid.emplace(vm.vm_uid, std::move(vm));
            }
            catch (const std::exception& e)
            {
                mpl::log_message(mpl::Level::warning,
                                 category,
                                 fmt::format("skipping v1 or invalid registry row: {}", e.what()));
            }
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
    record.source = normalize_vm_source(record.source);
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
    const std::string& vm_name,
    std::string_view source) const
{
    const auto wanted = normalize_vm_source(source);
    std::lock_guard lock{mutex};
    for (const auto& [_, vm] : by_uid)
    {
        if (vm.vm_name == vm_name && normalize_vm_source(vm.source) == wanted)
            return vm;
    }
    return std::nullopt;
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
