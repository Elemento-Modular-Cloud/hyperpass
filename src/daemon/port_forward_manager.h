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

#include <multipass/disabled_copy_move.h>
#include <multipass/port_forward.h>

#include <QObject>
#include <QTcpServer>

#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace multipass
{
class PortForwardManager : public QObject, private DisabledCopyMove
{
    Q_OBJECT
public:
    struct RuntimeStatus
    {
        bool active{false};
        std::string guest_ip;
        std::string status_message;
    };

    explicit PortForwardManager(QObject* parent = nullptr);

    // Start listening and splice to guest_ip:guest_port. Returns error message on failure.
    std::optional<std::string> activate(const PortForwardRule& rule, const std::string& guest_ip);
    void deactivate(const std::string& id);
    void deactivate_all_for(const std::string& instance);
    void deactivate_all();

    bool is_active(const std::string& id) const;
    RuntimeStatus status(const std::string& id) const;
    std::string active_guest_ip(const std::string& id) const;

private:
    struct ActiveForward
    {
        PortForwardRule rule;
        std::string guest_ip;
        std::unique_ptr<QTcpServer> server;
        std::string status_message;
    };

    void splice_connection(QTcpSocket* client, const std::string& guest_ip, int guest_port);

    std::unordered_map<std::string, ActiveForward> active;
};
} // namespace multipass
