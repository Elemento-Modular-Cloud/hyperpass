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

#include <multipass/mdns_service.h>

namespace mp = multipass;

namespace
{
// No mDNS backend on this platform (or the real one failed to initialize): the migration
// screen's host list simply has no "discovered" entries, and the user falls back to the
// always-available "known hosts" manual list.
class NoopMdnsService : public mp::MdnsService
{
public:
    void start() override
    {
    }
};
} // namespace

std::unique_ptr<mp::MdnsService> mp::make_mdns_service(MdnsAdvertisement)
{
    return std::make_unique<NoopMdnsService>();
}
