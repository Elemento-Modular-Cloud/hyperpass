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

#include "marketplace_cloud_init.h"

#ifndef CPPHTTPLIB_OPENSSL_SUPPORT
#define CPPHTTPLIB_OPENSSL_SUPPORT
#endif
#include <httplib.h>
#include <yaml-cpp/yaml.h>

#include <multipass/format.h>
#include <multipass/logging/log.h>

#include <boost/json.hpp>

#include <QDir>
#include <QFile>
#include <QUrl>

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <regex>
#include <stdexcept>

namespace mp = multipass;
namespace mpl = multipass::logging;
namespace json = boost::json;

namespace
{
constexpr auto category = "marketplace-cloud-init";
constexpr auto gateway_ca_guest_path = "/usr/local/share/ca-certificates/elp-llm-gateway.crt";
const std::regex version_suffix{R"(_v(\d+)$)"};

std::string env_or_empty(const char* key)
{
    const auto* value = std::getenv(key);
    return value ? std::string{value} : std::string{};
}

int directory_suffix_version(std::string_view id)
{
    const std::string id_str{id};
    std::smatch match;
    if (!std::regex_search(id_str, match, version_suffix))
        return 0;
    return std::stoi(match[1].str());
}

int compare_dotted_versions(std::string_view a, std::string_view b)
{
    auto parse = [](std::string_view v) {
        std::vector<int> parts;
        std::string cur;
        for (char c : v)
        {
            if (c == '.')
            {
                parts.push_back(cur.empty() ? 0 : std::stoi(cur));
                cur.clear();
            }
            else if (std::isdigit(static_cast<unsigned char>(c)))
                cur.push_back(c);
        }
        if (!cur.empty() || !v.empty())
            parts.push_back(cur.empty() ? 0 : std::stoi(cur));
        return parts;
    };
    const auto left = parse(a);
    const auto right = parse(b);
    const auto n = std::max(left.size(), right.size());
    for (size_t i = 0; i < n; ++i)
    {
        const auto x = i < left.size() ? left[i] : 0;
        const auto y = i < right.size() ? right[i] : 0;
        if (x != y)
            return x < y ? -1 : 1;
    }
    return 0;
}

int compare_service_versions(const mp::api::MarketplaceService& a, const mp::api::MarketplaceService& b)
{
    const auto by_version = compare_dotted_versions(a.version, b.version);
    if (by_version != 0)
        return by_version;
    return directory_suffix_version(a.id) - directory_suffix_version(b.id);
}

QDir resolve_services_dir(const QString& path)
{
    QDir root{path};
    QDir nested{root.filePath("services")};
    if (nested.exists())
        return nested;
    return root;
}

void collect_files(const QDir& dir, const QString& prefix, std::unordered_map<std::string, std::string>& out)
{
    const auto entries = dir.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot);
    for (const auto& info : entries)
    {
        const auto name = info.fileName();
        if (name == ".DS_Store" || name == "Thumbs.db" || name.endsWith('~') || name.endsWith(".swp"))
            continue;
        const auto relative = prefix.isEmpty() ? name : prefix + "/" + name;
        if (info.isDir())
        {
            collect_files(QDir{info.absoluteFilePath()}, relative, out);
            continue;
        }
        QFile file{info.absoluteFilePath()};
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const auto bytes = file.readAll();
        if (bytes.contains('\0'))
            continue;
        out.emplace(relative.toStdString(), bytes.toStdString());
    }
}

mp::api::MarketplaceService service_from_sources(std::string id,
                                                 std::unordered_map<std::string, std::string> sources)
{
    const auto manifest_it = sources.find("service.yaml");
    if (manifest_it == sources.end())
        throw std::runtime_error(fmt::format("service '{}' has no service.yaml", id));

    const auto manifest = YAML::Load(manifest_it->second);
    mp::api::MarketplaceService service;
    service.id = std::move(id);
    service.sources = std::move(sources);
    if (manifest["metadata"] && manifest["metadata"]["version"])
        service.version = manifest["metadata"]["version"].as<std::string>();

    service.entrypoint = "cloud-init.yaml";
    if (manifest["cloud_init"] && manifest["cloud_init"]["entrypoint"])
        service.entrypoint = manifest["cloud_init"]["entrypoint"].as<std::string>();
    if (!service.sources.contains(service.entrypoint))
        throw std::runtime_error(fmt::format("service '{}' missing entrypoint '{}'",
                                             service.id,
                                             service.entrypoint));

    if (manifest["files"] && manifest["files"].IsSequence())
    {
        for (const auto& spec : manifest["files"])
        {
            mp::api::MarketplaceFileSpec file;
            file.source = spec["source"].as<std::string>();
            file.destination = spec["destination"].as<std::string>();
            if (spec["owner"])
                file.owner = spec["owner"].as<std::string>();
            if (spec["permissions"])
                file.permissions = spec["permissions"].as<std::string>();
            service.files.push_back(std::move(file));
        }
    }

    if (manifest["prerequisites"] && manifest["prerequisites"]["firewall"] &&
        manifest["prerequisites"]["firewall"].IsSequence())
    {
        for (const auto& rule : manifest["prerequisites"]["firewall"])
        {
            const auto direction = rule["direction"] ? rule["direction"].as<std::string>() : "ingress";
            if (direction != "ingress")
                continue;
            if (rule["port"])
                service.ingress_ports.push_back(rule["port"].as<int>());
        }
    }

    return service;
}

mp::api::MarketplaceLibrary library_from_dir(const QString& path)
{
    const auto services_dir = resolve_services_dir(path);
    if (!services_dir.exists())
        throw std::runtime_error(fmt::format("ELP_MARKETPLACE_DIR does not exist: {}", path.toStdString()));

    mp::api::MarketplaceLibrary library;
    for (const auto& name : services_dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name))
    {
        const QDir service_dir{services_dir.filePath(name)};
        if (!QFile::exists(service_dir.filePath("service.yaml")))
            continue;
        std::unordered_map<std::string, std::string> sources;
        collect_files(service_dir, {}, sources);
        try
        {
            library.services.push_back(service_from_sources(name.toStdString(), std::move(sources)));
        }
        catch (const std::exception& e)
        {
            mpl::log(mpl::Level::warning, category, "skipping marketplace service '{}': {}", name, e.what());
        }
    }
    if (library.services.empty())
        throw std::runtime_error(
            fmt::format("No services with a service.yaml found in {}", services_dir.path()));
    return library;
}

mp::api::MarketplaceLibrary library_from_bundle_json(std::string_view body)
{
    const auto parsed = json::parse(body);
    if (!parsed.is_object())
        throw std::runtime_error("marketplace bundle is not a JSON object");
    const auto& root = parsed.as_object();
    auto schema = 0;
    if (root.contains("schema") && root.at("schema").is_int64())
        schema = static_cast<int>(root.at("schema").as_int64());
    else if (root.contains("schema") && root.at("schema").is_uint64())
        schema = static_cast<int>(root.at("schema").as_uint64());
    if (schema != 1)
        throw std::runtime_error("unsupported marketplace bundle schema");
    if (!root.contains("services") || !root.at("services").is_array())
        throw std::runtime_error("marketplace bundle missing services");

    mp::api::MarketplaceLibrary library;
    for (const auto& item : root.at("services").as_array())
    {
        if (!item.is_object())
            continue;
        const auto& entry = item.as_object();
        if (!entry.contains("id") || !entry.at("id").is_string())
            continue;
        std::unordered_map<std::string, std::string> sources;
        if (entry.contains("files") && entry.at("files").is_object())
        {
            for (const auto& [key, value] : entry.at("files").as_object())
            {
                if (value.is_string())
                    sources.emplace(std::string(key), std::string(value.as_string()));
            }
        }
        try
        {
            library.services.push_back(
                service_from_sources(std::string(entry.at("id").as_string()), std::move(sources)));
        }
        catch (const std::exception& e)
        {
            mpl::log(mpl::Level::warning, category, "skipping marketplace bundle service: {}", e.what());
        }
    }
    if (library.services.empty())
        throw std::runtime_error("marketplace bundle contained no usable services");
    return library;
}

std::string fetch_url(const std::string& url_str)
{
    const QUrl url{QString::fromStdString(url_str)};
    if (!url.isValid() || url.scheme().isEmpty())
    {
        QFile file{QString::fromStdString(url_str)};
        if (!file.open(QIODevice::ReadOnly))
            throw std::runtime_error(fmt::format("failed to read marketplace bundle {}", url_str));
        return file.readAll().toStdString();
    }
    if (url.isLocalFile())
    {
        QFile file{url.toLocalFile()};
        if (!file.open(QIODevice::ReadOnly))
            throw std::runtime_error(fmt::format("failed to read marketplace bundle {}", url_str));
        return file.readAll().toStdString();
    }

    const auto host = url.host().toStdString();
    const auto scheme = url.scheme().toStdString();
    const auto port = url.port(scheme == "https" ? 443 : 80);
    const auto path = url.path().isEmpty() ? "/" : url.path().toStdString();
    const auto query = url.query().toStdString();
    const auto target = query.empty() ? path : path + "?" + query;

    httplib::Client client{fmt::format("{}://{}:{}", scheme, host, port)};
    client.set_connection_timeout(10);
    client.set_read_timeout(30);
    const auto res = client.Get(target);
    if (!res)
        throw std::runtime_error(fmt::format("failed to fetch marketplace bundle {}", url_str));
    if (res->status < 200 || res->status >= 300)
        throw std::runtime_error(
            fmt::format("marketplace bundle HTTP {} from {}", res->status, url_str));
    return res->body;
}

bool looks_like_pem(std::string_view pem)
{
    return pem.find("BEGIN CERTIFICATE") != std::string_view::npos;
}

bool node_text_contains(const YAML::Node& node, std::string_view needle)
{
    if (node.IsScalar())
        return node.as<std::string>().find(needle) != std::string::npos;
    if (node.IsSequence())
    {
        for (const auto& item : node)
        {
            if (node_text_contains(item, needle))
                return true;
        }
    }
    return false;
}

void ensure_string_in_sequence(YAML::Node node, const std::string& value)
{
    if (!node || !node.IsSequence())
        return;
    for (const auto& item : node)
    {
        if (item.IsScalar() && item.as<std::string>() == value)
            return;
    }
    node.push_back(value);
}
} // namespace

std::string mp::api::marketplace_service_family(std::string_view service_id)
{
    return std::regex_replace(std::string{service_id}, version_suffix, "");
}

const mp::api::MarketplaceService* mp::api::MarketplaceLibrary::lookup(std::string_view id) const
{
    for (const auto& service : services)
    {
        if (service.id == id)
            return &service;
    }
    const auto family = marketplace_service_family(id);
    const MarketplaceService* best = nullptr;
    for (const auto& service : services)
    {
        if (marketplace_service_family(service.id) != family)
            continue;
        if (!best || compare_service_versions(service, *best) > 0)
            best = &service;
    }
    return best;
}

mp::api::MarketplaceLibrary mp::api::load_marketplace_library()
{
    const auto dir = env_or_empty("ELP_MARKETPLACE_DIR");
    if (!dir.empty())
        return library_from_dir(QString::fromStdString(dir));

    const auto url = env_or_empty("ELP_MARKETPLACE_URL");
    if (!url.empty())
        return library_from_bundle_json(fetch_url(url));

    throw std::runtime_error(
        "marketplace is not configured; set ELP_MARKETPLACE_DIR or ELP_MARKETPLACE_URL");
}

std::string mp::api::render_marketplace_cloud_init(const MarketplaceService& service,
                                                   std::string_view gateway_ca_pem)
{
    const auto it = service.sources.find(service.entrypoint);
    if (it == service.sources.end())
        throw std::runtime_error(fmt::format("service '{}' missing entrypoint", service.id));

    auto config = YAML::Load(it->second);
    if (!config || !config.IsMap())
        throw std::runtime_error(
            fmt::format("service '{}' entrypoint is not a cloud-config mapping", service.id));

    if (!config["write_files"] || !config["write_files"].IsSequence())
        config["write_files"] = YAML::Node(YAML::NodeType::Sequence);
    for (const auto& spec : service.files)
    {
        const auto content = service.sources.find(spec.source);
        if (content == service.sources.end())
            throw std::runtime_error(fmt::format("service '{}' declares file '{}' which is not bundled",
                                                 service.id,
                                                 spec.source));
        YAML::Node file;
        file["path"] = spec.destination;
        file["owner"] = spec.owner;
        file["permissions"] = spec.permissions;
        file["content"] = content->second;
        config["write_files"].push_back(file);
    }

    if (!config["growpart"])
    {
        config["growpart"]["mode"] = "auto";
        config["growpart"]["devices"].push_back("/");
        config["growpart"]["ignore_growroot_disabled"] = true;
    }
    if (!config["resize_rootfs"])
        config["resize_rootfs"] = true;

    if (!config["packages"] || !config["packages"].IsSequence())
        config["packages"] = YAML::Node(YAML::NodeType::Sequence);
    ensure_string_in_sequence(config["packages"], "cloud-guest-utils");

    if (!config["runcmd"] || !config["runcmd"].IsSequence())
        config["runcmd"] = YAML::Node(YAML::NodeType::Sequence);
    if (!node_text_contains(config["runcmd"], "growpart"))
    {
        YAML::Node grow;
        grow = "/bin/sh -c 'set -eux; src=$(readlink -f \"$(findmnt -n -o SOURCE /)\"); "
               "disk=\"/dev/$(lsblk -no PKNAME \"$src\")\"; part=$(lsblk -no PARTN \"$src\"); "
               "growpart \"$disk\" \"$part\" || true; resize2fs \"$src\" || true; df -h /'";
        YAML::Node next(YAML::NodeType::Sequence);
        next.push_back(grow);
        for (const auto& item : config["runcmd"])
            next.push_back(item);
        config["runcmd"] = next;
    }

    if (looks_like_pem(gateway_ca_pem))
    {
        bool already = false;
        for (const auto& file : config["write_files"])
        {
            if (file["path"] && file["path"].as<std::string>() == gateway_ca_guest_path)
                already = true;
        }
        if (!already)
        {
            YAML::Node ca;
            ca["path"] = gateway_ca_guest_path;
            ca["owner"] = "root:root";
            ca["permissions"] = "0644";
            auto pem = std::string{gateway_ca_pem};
            if (pem.empty() || pem.back() != '\n')
                pem.push_back('\n');
            ca["content"] = pem;
            YAML::Node files(YAML::NodeType::Sequence);
            files.push_back(ca);
            for (const auto& file : config["write_files"])
                files.push_back(file);
            config["write_files"] = files;
        }
        ensure_string_in_sequence(config["packages"], "ca-certificates");
        if (!node_text_contains(config["runcmd"], "update-ca-certificates"))
        {
            YAML::Node next(YAML::NodeType::Sequence);
            next.push_back("update-ca-certificates");
            for (const auto& item : config["runcmd"])
                next.push_back(item);
            config["runcmd"] = next;
        }
    }

    auto dumped = YAML::Dump(config);
    if (dumped.rfind("#cloud-config", 0) != 0)
        dumped = "#cloud-config\n" + dumped;
    if (!dumped.empty() && dumped.back() != '\n')
        dumped.push_back('\n');
    return dumped;
}

std::int64_t mp::api::first_marketplace_ingress_port(const MarketplaceService& service)
{
    if (service.ingress_ports.empty())
        return 0;
    return service.ingress_ports.front();
}
