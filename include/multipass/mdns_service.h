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

#pragma once

#include <QObject>

#include <memory>
#include <string>

namespace multipass
{

// Advertised/discovered over the "_elp._tcp" mDNS service type. host_name/host_os/host_arch
// mirror DaemonInfoReply's own fields (see daemon_info's handler); a peer's label is its mDNS
// service instance name (not necessarily its host_name).
struct MdnsHostInfo
{
    std::string label;
    std::string address; // resolved IP (or hostname, if resolution only gets that far)
    std::string host_name;
    std::string host_os;
    std::string host_arch;
    std::string backend;
};

struct MdnsAdvertisement
{
    std::string label; // mDNS service instance name for this daemon; default: host_name
    std::string host_name;
    std::string host_os;
    std::string host_arch;
    std::string backend;
};

// Advertises this elpd as "_elp._tcp" on the local network and browses for other instances
// of it, so the GUI's migration screen can offer a live list of candidate hosts alongside the
// manually-added "known hosts" list (list_network_hosts merges both — see Daemon::migrate's
// own doc comment on why migration itself doesn't talk to a peer's elpd directly: this service
// is purely informational/discovery, migration itself goes over SSH to the target's own CLI).
class MdnsService : public QObject
{
    Q_OBJECT
public:
    ~MdnsService() override = default;

    // Begins advertising + browsing. Safe to call once; browsing/advertising continue until
    // this object is destroyed. Never throws — failures (no mDNS daemon reachable, etc.) are
    // logged and leave this a permanently-inert no-op rather than taking elpd down with it.
    virtual void start() = 0;

signals:
    // Always emitted on this object's own thread; connect with an auto/queued connection to
    // observe from Daemon's thread (see mdns_service_linux.cpp/mdns_service_macos.cpp — both
    // run their platform library's event loop on a dedicated worker thread).
    void host_discovered(multipass::MdnsHostInfo info);
    void host_removed(std::string label);

protected:
    MdnsService();
};

// Returns a platform-appropriate implementation (Avahi on Linux, Bonjour/dns_sd on macOS), or
// a permanently-inert no-op elsewhere (e.g. Windows) so callers never need to branch on
// platform themselves.
std::unique_ptr<MdnsService> make_mdns_service(MdnsAdvertisement advertisement);

} // namespace multipass

Q_DECLARE_METATYPE(multipass::MdnsHostInfo)
