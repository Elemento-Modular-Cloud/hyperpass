/*
 * Copyright (C) Canonical, Ltd.
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

#include <multipass/base_availability_zone.h>
#include <multipass/base_availability_zone_manager.h>
#include <multipass/exceptions/availability_zone_exceptions.h>
#include <multipass/file_ops.h>
#include <multipass/json_utils.h>
#include <multipass/logging/log.h>
#include <multipass/platform.h>

#include <fmt/format.h>

#include <optional>
#include <utility>

namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "az-manager";
constexpr auto az_file = "az-manager.json";
constexpr auto zones_directory_name = "zones";
constexpr auto automatic_zone_key = "automatic_zone";
constexpr auto preferred_subnet_key = "preferred_subnet";

struct ManagerFile
{
    std::string automatic_zone;
    std::optional<std::string> preferred_subnet;
};

[[nodiscard]] ManagerFile load_manager_file(const multipass::fs::path& file_path)
{
    mpl::debug(category, "reading AZ manager from file '{}'", file_path);
    if (auto filedata = MP_FILEOPS.try_read_file(file_path))
    {
        try
        {
            auto json = boost::json::parse(*filedata);
            ManagerFile loaded{
                .automatic_zone = boost::json::value_to<std::string>(json.at(automatic_zone_key)),
                .preferred_subnet = std::nullopt,
            };
            if (const auto* preferred = json.as_object().if_contains(preferred_subnet_key))
                loaded.preferred_subnet = boost::json::value_to<std::string>(*preferred);
            return loaded;
        }
        catch (const boost::system::system_error& e)
        {
            mpl::error(category, "Error parsing file '{}': {}", file_path, e.what());
        }
    }
    return {};
}

void reset_zone_files_if_preferred_changed(const multipass::fs::path& zones_directory,
                                           const ManagerFile& loaded,
                                           const multipass::Subnet& preferred)
{
    const auto preferred_cidr = preferred.to_cidr();
    if (loaded.preferred_subnet && *loaded.preferred_subnet == preferred_cidr)
        return;

    mpl::warn(category,
              "Preferred subnet changed ({} -> {}); reallocating zone subnets",
              loaded.preferred_subnet.value_or("<unset>"),
              preferred_cidr);

    for (const auto& zone_name : multipass::default_zone_names)
    {
        const auto zone_file = zones_directory / (std::string{zone_name} + ".json");
        MP_FILEOPS.remove(zone_file);
    }
}

[[nodiscard]] auto create_default_zones(const multipass::fs::path& zones_directory,
                                        multipass::SubnetAllocator& subnet_allocator)
{
    using namespace multipass;

    std::array<AvailabilityZone::UPtr, default_zone_names.size()> zones{};
    size_t idx = 0;
    for (const auto& zone_name : default_zone_names)
        zones[idx++] = std::make_unique<BaseAvailabilityZone>(zone_name,
                                                              zones_directory,
                                                              subnet_allocator);

    return zones;
}
} // namespace

namespace multipass
{

BaseAvailabilityZoneManager::BaseAvailabilityZoneManager(const fs::path& data_dir)
    : file_path{data_dir / az_file},
      preferred_subnet{MP_PLATFORM.get_preferred_subnet(data_dir)},
      subnet_allocator{preferred_subnet, subnet_prefix_length},
      zone_collection{
          make_zone_collection(data_dir, file_path, preferred_subnet, subnet_allocator)}
{
    save_file();
}

BaseAvailabilityZoneManager::ZoneCollection BaseAvailabilityZoneManager::make_zone_collection(
    const fs::path& data_dir,
    const fs::path& file_path,
    const Subnet& preferred,
    SubnetAllocator& subnet_allocator)
{
    const auto loaded = load_manager_file(file_path);
    reset_zone_files_if_preferred_changed(data_dir / zones_directory_name, loaded, preferred);
    return ZoneCollection{create_default_zones(data_dir / zones_directory_name, subnet_allocator),
                          loaded.automatic_zone};
}

AvailabilityZone& BaseAvailabilityZoneManager::get_zone(const std::string& name)
{
    return const_cast<AvailabilityZone&>(std::as_const(*this).get_zone(name));
}

const AvailabilityZone& BaseAvailabilityZoneManager::get_zone(const std::string& name) const
{
    for (const auto& zone : zones())
    {
        if (zone->get_name() == name)
            return *zone;
    }
    throw AvailabilityZoneNotFound{name};
}

std::string BaseAvailabilityZoneManager::get_automatic_zone_name()
{
    const auto zone_name = zone_collection.next_available();
    save_file();
    return zone_name;
}

std::vector<std::reference_wrapper<const AvailabilityZone>>
BaseAvailabilityZoneManager::get_zones() const
{
    std::vector<std::reference_wrapper<const AvailabilityZone>> zone_list;
    zone_list.reserve(zones().size());
    for (auto& zone : zones())
        zone_list.emplace_back(*zone);
    return zone_list;
}

std::string BaseAvailabilityZoneManager::get_default_zone_name() const
{
    return (*zones().begin())->get_name();
}

void BaseAvailabilityZoneManager::save_file() const
{
    mpl::debug(category, "writing AZ manager to file '{}'", file_path);
    const std::unique_lock lock{mutex};

    boost::json::value json = {{automatic_zone_key, zone_collection.last_used()},
                               {preferred_subnet_key, preferred_subnet.to_cidr()}};
    MP_FILEOPS.write_transactionally(QString::fromStdString(file_path.string()),
                                     pretty_print(json));
}

const BaseAvailabilityZoneManager::ZoneCollection::ZoneArray&
BaseAvailabilityZoneManager::zones() const
{
    return zone_collection.zones;
}

BaseAvailabilityZoneManager::ZoneCollection::ZoneCollection(
    std::array<AvailabilityZone::UPtr, default_zone_names.size()>&& _zones,
    std::string last_used)
    : zones{std::move(_zones)},
      automatic_zone{std::find_if(zones.begin(), zones.end(), [&last_used](const auto& zone) {
          return zone->get_name() == last_used;
      })}
{
    if (automatic_zone == zones.end())
    {
        mpl::debug(category, "automatic zone '{}' not known, using default", last_used);
        automatic_zone = zones.begin();
    }
}

std::string BaseAvailabilityZoneManager::ZoneCollection::next_available()
{
    std::unique_lock lock{mutex};

    // Locate the first available zone
    auto zone_it = std::find_if(zones.begin(), zones.end(), [](const auto& zone) {
        return zone->is_available();
    });

    // Check if an available zone was found
    if (zone_it != zones.end())
    {
        automatic_zone = zone_it;
        return (*zone_it)->get_name();
    }

    // If none are available, throw an exception
    throw NoAvailabilityZoneAvailable{};
}

std::string BaseAvailabilityZoneManager::ZoneCollection::last_used() const
{
    std::shared_lock lock{mutex};
    return automatic_zone->get()->get_name();
}

} // namespace multipass
