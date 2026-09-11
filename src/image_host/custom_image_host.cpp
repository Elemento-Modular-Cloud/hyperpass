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

#include <multipass/constants.h>
#include <multipass/exceptions/download_exception.h>
#include <multipass/exceptions/image_not_found_exception.h>
#include <multipass/exceptions/unsupported_arch_exception.h>
#include <multipass/file_ops.h>
#include <multipass/image_host/custom_image_host.h>
#include <multipass/logging/log.h>
#include <multipass/query.h>
#include <multipass/url_downloader.h>
#include <multipass/utils.h>

#include <fmt/format.h>

#include <boost/json.hpp>

#include <QFile>
#include <QUrl>

#include <optional>
#include <utility>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "custom_image_host";
constexpr auto no_remote{""};

auto get_manifest_url()
{
    return qEnvironmentVariable(mp::distributions_url_env_var).isEmpty()
             ? QString{mp::default_distributions_url}
             : qEnvironmentVariable(mp::distributions_url_env_var);
}

std::optional<QString> local_manifest_path(const QString& source)
{
    const QUrl url{source, QUrl::TolerantMode};
    const auto scheme = url.scheme().toLower();

    if (scheme == QLatin1String("http") || scheme == QLatin1String("https"))
        return std::nullopt;

    if (url.isLocalFile())
        return url.toLocalFile();

    // Bare paths (including missing files) and Windows drive-letter paths.
    if (scheme.isEmpty() || (scheme.size() == 1 && scheme[0].isLetter()))
        return source;

    return std::nullopt;
}

QByteArray read_local_manifest(const QString& path)
{
    QFile file{path};
    if (!MP_FILEOPS.exists(file) || !MP_FILEOPS.open(file, QIODevice::ReadOnly))
        throw mp::DownloadException{path.toStdString(), "file not found or unreadable"};

    return MP_FILEOPS.read_all(file);
}

QByteArray load_manifest_data(mp::URLDownloader* url_downloader, bool force_update)
{
    const auto source = get_manifest_url();
    mpl::log(mpl::Level::debug, category, "Fetching images from {}", source);

    if (const auto path = local_manifest_path(source))
        return read_local_manifest(*path);

    return url_downloader->download(QUrl{source}, force_update);
}

std::vector<mp::VMImageInfo> fetch_image_info(const std::string& arch,
                                              mp::URLDownloader* url_downloader,
                                              bool force_update = false)
{
    try
    {
        auto data = load_manifest_data(url_downloader, force_update);
        auto manifest = boost::json::parse(std::string_view(data)).as_object();
        mpl::log(mpl::Level::debug, category, "Found {} items", manifest.size());

        mp::ArchContext context{arch};
        std::vector<mp::VMImageInfo> result;
        for (const auto& [distro_name, value] : manifest)
        {
            try
            {
                result.push_back(value_to<mp::VMImageInfo>(value, context));
            }
            catch (const mp::UnsupportedArchException&)
            {
                mpl::debug(category,
                           "Skipping unsupported distro '{}' for arch '{}'",
                           distro_name,
                           arch);
                continue;
            }
        }
        return result;
    }
    catch (mp::DownloadException& e)
    {
        mpl::log(mpl::Level::warning, category, "Failed to load manifest: {}", e);
        return {};
    }
    catch (const boost::system::system_error&)
    {
        mpl::log(mpl::Level::warning,
                 category,
                 "Failed to parse manifest: file does not contain a valid JSON object");
        return {};
    }
}
} // namespace

mp::CustomManifest::CustomManifest(std::vector<VMImageInfo>&& images)
    : products{std::move(images)}, image_records{map_aliases_to_vm_info(products)}
{
}

mp::CustomVMImageHost::CustomVMImageHost(URLDownloader* downloader)
    : BaseVMImageHost{downloader},
      arch{QSysInfo::currentCpuArchitecture().toStdString()},
      manifest{},
      remote{no_remote}
{
}

std::optional<mp::VMImageInfo> mp::CustomVMImageHost::info_for_impl(const Query& query) const
{
    const auto& custom_manifest = manifest_from(query.remote_name);

    auto it = custom_manifest.image_records.find(query.release);

    if (it == custom_manifest.image_records.end())
        return std::nullopt;

    return *it->second;
}

std::vector<std::pair<std::string, mp::VMImageInfo>> mp::CustomVMImageHost::all_info_for_impl(
    const Query& query) const
{
    std::vector<std::pair<std::string, mp::VMImageInfo>> images;

    if (auto image = info_for_impl(query))
        images.emplace_back(query.remote_name, std::move(*image));

    return images;
}

std::vector<mp::VMImageInfo> mp::CustomVMImageHost::all_images_for_impl(
    const std::string& remote_name,
    bool /*allow_unsupported*/) const
{
    return manifest_from(remote_name).products;
}

std::vector<std::string> mp::CustomVMImageHost::supported_remotes() const
{
    return {remote};
}

void mp::CustomVMImageHost::for_each_entry_do_impl(const Action& action) const
{
    for (const auto& info : manifest.second->products)
    {
        action(manifest.first, info);
    }
}

mp::VMImageInfo mp::CustomVMImageHost::info_for_full_hash_impl(const std::string& full_hash) const
{
    for (const auto& product : manifest.second->products)
    {
        if (multipass::utils::iequals(product.id, full_hash))
        {
            return product;
        }
    }

    throw mp::ImageNotFoundException(full_hash);
}

void mp::CustomVMImageHost::fetch_manifests(bool force_update)
{
    try
    {
        auto custom_manifest = std::make_unique<mp::CustomManifest>(
            fetch_image_info(arch, url_downloader, force_update));
        manifest = std::make_pair(no_remote, std::move(custom_manifest));
    }
    catch (mp::DownloadException& e)
    {
        throw e;
    }
}

void mp::CustomVMImageHost::clear()
{
    manifest = std::pair<std::string, std::unique_ptr<CustomManifest>>{};
}

const mp::CustomManifest& mp::CustomVMImageHost::manifest_from(const std::string& remote_name) const
{
    if (remote_name != manifest.first || !manifest.second)
        throw std::runtime_error(
            fmt::format("Remote \"{}\" is unknown or unreachable.", remote_name));

    return *manifest.second;
}
