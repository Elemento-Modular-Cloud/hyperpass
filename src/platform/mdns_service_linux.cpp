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

#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/mdns_service.h>

#include <avahi-client/client.h>
#include <avahi-client/lookup.h>
#include <avahi-client/publish.h>
#include <avahi-common/error.h>
#include <avahi-common/malloc.h>
#include <avahi-common/thread-watch.h>

#include <cstring>
#include <net/if.h>
#include <unordered_set>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "mdns";
constexpr auto service_type = "_elp._tcp";
// Purely informational: nothing actually listens here. Migration itself talks to a target's
// own local elp CLI over SSH, not to a peer elpd directly — see Daemon::migrate.
constexpr std::uint16_t advertised_port = 7773;

std::string txt_value(AvahiStringList* txt, const char* key)
{
    if (!txt)
        return {};
    auto* node = avahi_string_list_find(txt, key);
    if (!node)
        return {};
    char* k = nullptr;
    char* v = nullptr;
    size_t size = 0;
    if (avahi_string_list_get_pair(node, &k, &v, &size) != 0)
        return {};
    std::string result = v ? std::string(v, size) : std::string{};
    avahi_free(k);
    avahi_free(v);
    return result;
}

class AvahiMdnsService : public mp::MdnsService
{
public:
    explicit AvahiMdnsService(mp::MdnsAdvertisement advertisement)
        : advertisement{std::move(advertisement)}
    {
    }

    ~AvahiMdnsService() override
    {
        if (threaded_poll)
            avahi_threaded_poll_stop(threaded_poll);

        // Resolvers may still be outstanding; free whatever's left before the client/poll go.
        for (auto* resolver : live_resolvers)
            avahi_service_resolver_free(resolver);
        if (browser)
            avahi_service_browser_free(browser);
        if (entry_group)
            avahi_entry_group_free(entry_group);
        if (client)
            avahi_client_free(client);
        if (threaded_poll)
            avahi_threaded_poll_free(threaded_poll);
    }

    void start() override
    {
        threaded_poll = avahi_threaded_poll_new();
        if (!threaded_poll)
        {
            mpl::log(mpl::Level::warning, category, "avahi_threaded_poll_new failed");
            return;
        }

        int error = 0;
        client = avahi_client_new(avahi_threaded_poll_get(threaded_poll),
                                  AVAHI_CLIENT_NO_FAIL,
                                  &AvahiMdnsService::client_callback,
                                  this,
                                  &error);
        if (!client)
        {
            mpl::log(mpl::Level::warning, category, "avahi_client_new failed: {}", avahi_strerror(error));
            avahi_threaded_poll_free(threaded_poll);
            threaded_poll = nullptr;
            return;
        }

        if (avahi_threaded_poll_start(threaded_poll) != 0)
        {
            mpl::log(mpl::Level::warning, category, "avahi_threaded_poll_start failed");
            avahi_client_free(client);
            client = nullptr;
            avahi_threaded_poll_free(threaded_poll);
            threaded_poll = nullptr;
        }
    }

private:
    // --- Advertising ---------------------------------------------------------------------

    void create_services()
    {
        entry_group = avahi_entry_group_new(client, &AvahiMdnsService::entry_group_callback, this);
        if (!entry_group)
        {
            mpl::log(mpl::Level::warning,
                    category,
                    "avahi_entry_group_new failed: {}",
                    avahi_strerror(avahi_client_errno(client)));
            return;
        }

        const auto label = advertisement.label.empty() ? advertisement.host_name : advertisement.label;
        const auto host_name_txt = fmt::format("host_name={}", advertisement.host_name);
        const auto host_os_txt = fmt::format("host_os={}", advertisement.host_os);
        const auto host_arch_txt = fmt::format("host_arch={}", advertisement.host_arch);
        const auto backend_txt = fmt::format("backend={}", advertisement.backend);

        auto ret = avahi_entry_group_add_service(entry_group,
                                                 AVAHI_IF_UNSPEC,
                                                 AVAHI_PROTO_UNSPEC,
                                                 AvahiPublishFlags{},
                                                 label.c_str(),
                                                 service_type,
                                                 nullptr,
                                                 nullptr,
                                                 advertised_port,
                                                 host_name_txt.c_str(),
                                                 host_os_txt.c_str(),
                                                 host_arch_txt.c_str(),
                                                 backend_txt.c_str(),
                                                 nullptr);
        if (ret < 0)
        {
            mpl::log(mpl::Level::warning,
                    category,
                    "avahi_entry_group_add_service failed: {}",
                    avahi_strerror(ret));
            return;
        }

        ret = avahi_entry_group_commit(entry_group);
        if (ret < 0)
            mpl::log(mpl::Level::warning, category, "avahi_entry_group_commit failed: {}", avahi_strerror(ret));
    }

    static void entry_group_callback(AvahiEntryGroup*, AvahiEntryGroupState state, void*)
    {
        if (state == AVAHI_ENTRY_GROUP_COLLISION)
            mpl::log(mpl::Level::warning,
                    category,
                    "mDNS service name collision advertising this host; not retrying in v1");
        else if (state == AVAHI_ENTRY_GROUP_FAILURE)
            mpl::log(mpl::Level::warning, category, "mDNS entry group failure");
    }

    // --- Browsing --------------------------------------------------------------------------

    void create_browser()
    {
        browser = avahi_service_browser_new(client,
                                            AVAHI_IF_UNSPEC,
                                            AVAHI_PROTO_UNSPEC,
                                            service_type,
                                            nullptr,
                                            AvahiLookupFlags{},
                                            &AvahiMdnsService::browse_callback,
                                            this);
        if (!browser)
            mpl::log(mpl::Level::warning,
                    category,
                    "avahi_service_browser_new failed: {}",
                    avahi_strerror(avahi_client_errno(client)));
    }

    static void browse_callback(AvahiServiceBrowser*,
                               AvahiIfIndex interface,
                               AvahiProtocol protocol,
                               AvahiBrowserEvent event,
                               const char* name,
                               const char* type,
                               const char* domain,
                               AvahiLookupResultFlags,
                               void* userdata)
    {
        auto* self = static_cast<AvahiMdnsService*>(userdata);
        if (event == AVAHI_BROWSER_NEW)
        {
            // Skip our own advertisement.
            if (self->advertisement.label == name ||
                (self->advertisement.label.empty() && self->advertisement.host_name == name))
                return;

            auto* resolver = avahi_service_resolver_new(self->client,
                                                        interface,
                                                        protocol,
                                                        name,
                                                        type,
                                                        domain,
                                                        AVAHI_PROTO_UNSPEC,
                                                        AvahiLookupFlags{},
                                                        &AvahiMdnsService::resolve_callback,
                                                        self);
            if (resolver)
                self->live_resolvers.insert(resolver);
        }
        else if (event == AVAHI_BROWSER_REMOVE)
        {
            emit self->host_removed(std::string(name));
        }
        else if (event == AVAHI_BROWSER_FAILURE)
        {
            mpl::log(mpl::Level::warning,
                    category,
                    "mDNS browse failure: {}",
                    avahi_strerror(avahi_client_errno(self->client)));
        }
    }

    static void resolve_callback(AvahiServiceResolver* r,
                                AvahiIfIndex interface,
                                AvahiProtocol,
                                AvahiResolverEvent event,
                                const char* name,
                                const char*,
                                const char*,
                                const char* host_name,
                                const AvahiAddress* address,
                                uint16_t,
                                AvahiStringList* txt,
                                AvahiLookupResultFlags,
                                void* userdata)
    {
        auto* self = static_cast<AvahiMdnsService*>(userdata);

        if (event == AVAHI_RESOLVER_FOUND)
        {
            char address_str[AVAHI_ADDRESS_STR_MAX];
            avahi_address_snprint(address_str, sizeof(address_str), address);

            std::string resolved_address = address_str;
            // An IPv6 link-local address (fe80::/10) is only routable with an interface
            // zone id attached (e.g. "fe80::1%eth0") — without it, ssh/getaddrinfo silently
            // hang/timeout trying to reach it. mDNS replies commonly come back link-local,
            // so this isn't an edge case: it's the common failure mode on real LANs.
            if (address->proto == AVAHI_PROTO_INET6 &&
                address->data.ipv6.address[0] == 0xfe &&
                (address->data.ipv6.address[1] & 0xc0) == 0x80 &&
                interface != AVAHI_IF_UNSPEC)
            {
                char ifname[IF_NAMESIZE];
                if (if_indextoname(static_cast<unsigned int>(interface), ifname))
                    resolved_address += fmt::format("%{}", ifname);
            }

            mp::MdnsHostInfo info;
            info.label = name ? name : "";
            info.address = resolved_address;
            info.host_name = txt_value(txt, "host_name");
            if (info.host_name.empty())
                info.host_name = host_name ? host_name : "";
            info.host_os = txt_value(txt, "host_os");
            info.host_arch = txt_value(txt, "host_arch");
            info.backend = txt_value(txt, "backend");

            emit self->host_discovered(info);
        }
        else
        {
            mpl::log(mpl::Level::debug, category, "mDNS resolve failed for {}", name ? name : "");
        }

        self->live_resolvers.erase(r);
        avahi_service_resolver_free(r);
    }

    static void client_callback(AvahiClient* c, AvahiClientState state, void* userdata)
    {
        auto* self = static_cast<AvahiMdnsService*>(userdata);
        self->client = c;

        switch (state)
        {
        case AVAHI_CLIENT_S_RUNNING:
            self->create_services();
            self->create_browser();
            break;
        case AVAHI_CLIENT_FAILURE:
            mpl::log(mpl::Level::warning, category, "mDNS client failure: {}", avahi_strerror(avahi_client_errno(c)));
            break;
        case AVAHI_CLIENT_S_COLLISION:
        case AVAHI_CLIENT_S_REGISTERING:
            if (self->entry_group)
                avahi_entry_group_reset(self->entry_group);
            break;
        case AVAHI_CLIENT_CONNECTING:
            break;
        }
    }

    mp::MdnsAdvertisement advertisement;
    AvahiThreadedPoll* threaded_poll{nullptr};
    AvahiClient* client{nullptr};
    AvahiEntryGroup* entry_group{nullptr};
    AvahiServiceBrowser* browser{nullptr};
    std::unordered_set<AvahiServiceResolver*> live_resolvers;
};
} // namespace

std::unique_ptr<mp::MdnsService> mp::make_mdns_service(MdnsAdvertisement advertisement)
{
    return std::make_unique<AvahiMdnsService>(std::move(advertisement));
}
