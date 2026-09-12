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

#include <QSocketNotifier>

#include <dns_sd.h>

#include <memory>
#include <unordered_map>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "mdns";
constexpr auto service_type = "_elp._tcp";
// Purely informational: nothing actually listens here. Migration itself talks to a target's
// own local elp CLI over SSH, not to a peer elpd directly — see Daemon::migrate.
constexpr std::uint16_t advertised_port = 7773;

// Wraps one DNSServiceRef with the QSocketNotifier that drives it from Qt's own event loop —
// dns_sd's classic API hands back a plain fd (DNSServiceRefSockFD) to poll/select on and expects
// DNSServiceProcessResult() to be called when it's readable, which is a much more natural fit
// for Qt than Avahi's API (see mdns_service_linux.cpp's dedicated AvahiThreadedPoll thread) —
// no separate thread needed here.
class ServiceRefWatcher : public QObject
{
public:
    ServiceRefWatcher(DNSServiceRef ref, QObject* parent) : QObject{parent}, ref{ref}
    {
        notifier = std::make_unique<QSocketNotifier>(DNSServiceRefSockFD(ref),
                                                      QSocketNotifier::Read,
                                                      this);
        connect(notifier.get(), &QSocketNotifier::activated, this, [this] {
            const auto err = DNSServiceProcessResult(this->ref);
            if (err != kDNSServiceErr_NoError)
                mpl::log(mpl::Level::debug, category, "DNSServiceProcessResult error: {}", err);
        });
    }

    ~ServiceRefWatcher() override
    {
        DNSServiceRefDeallocate(ref);
    }

private:
    DNSServiceRef ref;
    std::unique_ptr<QSocketNotifier> notifier;
};

class BonjourMdnsService : public mp::MdnsService
{
public:
    explicit BonjourMdnsService(mp::MdnsAdvertisement advertisement)
        : advertisement{std::move(advertisement)}
    {
    }

    void start() override
    {
        register_service();
        browse();
    }

private:
    void register_service()
    {
        TXTRecordRef txt;
        TXTRecordCreate(&txt, 0, nullptr);
        TXTRecordSetValue(&txt,
                          "host_name",
                          static_cast<std::uint8_t>(advertisement.host_name.size()),
                          advertisement.host_name.data());
        TXTRecordSetValue(&txt,
                          "host_os",
                          static_cast<std::uint8_t>(advertisement.host_os.size()),
                          advertisement.host_os.data());
        TXTRecordSetValue(&txt,
                          "host_arch",
                          static_cast<std::uint8_t>(advertisement.host_arch.size()),
                          advertisement.host_arch.data());
        TXTRecordSetValue(&txt,
                          "backend",
                          static_cast<std::uint8_t>(advertisement.backend.size()),
                          advertisement.backend.data());

        DNSServiceRef ref{nullptr};
        const auto label = advertisement.label.empty() ? advertisement.host_name : advertisement.label;
        const auto err = DNSServiceRegister(&ref,
                                           0,
                                           0,
                                           label.empty() ? nullptr : label.c_str(),
                                           service_type,
                                           nullptr,
                                           nullptr,
                                           htons(advertised_port),
                                           TXTRecordGetLength(&txt),
                                           TXTRecordGetBytesPtr(&txt),
                                           &BonjourMdnsService::register_callback,
                                           this);
        TXTRecordDeallocate(&txt);

        if (err != kDNSServiceErr_NoError)
        {
            mpl::log(mpl::Level::warning, category, "DNSServiceRegister failed: {}", err);
            return;
        }
        register_watcher = std::make_unique<ServiceRefWatcher>(ref, this);
    }

    void browse()
    {
        DNSServiceRef ref{nullptr};
        const auto err = DNSServiceBrowse(&ref,
                                          0,
                                          0,
                                          service_type,
                                          nullptr,
                                          &BonjourMdnsService::browse_callback,
                                          this);
        if (err != kDNSServiceErr_NoError)
        {
            mpl::log(mpl::Level::warning, category, "DNSServiceBrowse failed: {}", err);
            return;
        }
        browse_watcher = std::make_unique<ServiceRefWatcher>(ref, this);
    }

    static void register_callback(DNSServiceRef,
                                  DNSServiceFlags,
                                  DNSServiceErrorType error,
                                  const char*,
                                  const char*,
                                  const char*,
                                  void*)
    {
        if (error != kDNSServiceErr_NoError)
            mpl::log(mpl::Level::warning, category, "DNSServiceRegister callback error: {}", error);
    }

    static void browse_callback(DNSServiceRef,
                               DNSServiceFlags flags,
                               uint32_t interface_index,
                               DNSServiceErrorType error,
                               const char* name,
                               const char* type,
                               const char* domain,
                               void* userdata)
    {
        auto* self = static_cast<BonjourMdnsService*>(userdata);
        if (error != kDNSServiceErr_NoError)
        {
            mpl::log(mpl::Level::warning, category, "DNSServiceBrowse callback error: {}", error);
            return;
        }

        if (flags & kDNSServiceFlagsAdd)
        {
            if (self->advertisement.label == name ||
                (self->advertisement.label.empty() && self->advertisement.host_name == name))
                return; // skip our own advertisement

            DNSServiceRef resolve_ref{nullptr};
            const auto err = DNSServiceResolve(&resolve_ref,
                                              0,
                                              interface_index,
                                              name,
                                              type,
                                              domain,
                                              &BonjourMdnsService::resolve_callback,
                                              self);
            if (err == kDNSServiceErr_NoError)
                self->resolve_watchers[name] =
                    std::make_unique<ServiceRefWatcher>(resolve_ref, self);
        }
        else
        {
            self->resolve_watchers.erase(name);
            emit self->host_removed(std::string(name));
        }
    }

    static void resolve_callback(DNSServiceRef,
                                DNSServiceFlags,
                                uint32_t,
                                DNSServiceErrorType error,
                                const char* full_name,
                                const char* host_target,
                                uint16_t,
                                uint16_t txt_len,
                                const unsigned char* txt_record,
                                void* userdata)
    {
        auto* self = static_cast<BonjourMdnsService*>(userdata);

        if (error != kDNSServiceErr_NoError)
        {
            mpl::log(mpl::Level::debug, category, "DNSServiceResolve error: {}", error);
            return;
        }

        auto txt_value = [&](const char* key) -> std::string {
            uint8_t value_len = 0;
            const auto* value = static_cast<const char*>(
                TXTRecordGetValuePtr(txt_len, txt_record, key, &value_len));
            return value ? std::string(value, value_len) : std::string{};
        };

        mp::MdnsHostInfo info;
        info.label = full_name ? full_name : "";
        info.address = host_target ? host_target : ""; // an mDNS .local hostname, directly SSH-able
        info.host_name = txt_value("host_name");
        info.host_os = txt_value("host_os");
        info.host_arch = txt_value("host_arch");
        info.backend = txt_value("backend");

        emit self->host_discovered(info);

        // One-shot: this backend doesn't keep resolving after the first answer, unlike browse.
        // Deferred via invokeMethod rather than erased here directly — erasing the
        // ServiceRefWatcher that owns the very DNSServiceRef this callback is running under
        // would destroy its QSocketNotifier from inside its own activated handler.
        const std::string key = full_name ? full_name : "";
        QMetaObject::invokeMethod(
            self, [self, key] { self->resolve_watchers.erase(key); }, Qt::QueuedConnection);
    }

    mp::MdnsAdvertisement advertisement;
    std::unique_ptr<ServiceRefWatcher> register_watcher;
    std::unique_ptr<ServiceRefWatcher> browse_watcher;
    std::unordered_map<std::string, std::unique_ptr<ServiceRefWatcher>> resolve_watchers;
};
} // namespace

std::unique_ptr<mp::MdnsService> mp::make_mdns_service(MdnsAdvertisement advertisement)
{
    return std::make_unique<BonjourMdnsService>(std::move(advertisement));
}
