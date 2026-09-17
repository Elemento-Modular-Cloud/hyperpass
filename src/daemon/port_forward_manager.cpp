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

#include "port_forward_manager.h"

#include <multipass/format.h>
#include <multipass/logging/log.h>

#include <QHostAddress>
#include <QTcpSocket>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "port-forward";
}

mp::PortForwardManager::PortForwardManager(QObject* parent) : QObject{parent}
{
}

std::optional<std::string> mp::PortForwardManager::activate(const PortForwardRule& rule,
                                                            const std::string& guest_ip)
{
    if (guest_ip.empty())
        return "Guest IP is unavailable";

    if (rule.host_port <= 0 || rule.host_port > 65535)
        return "Invalid host port";

    if (rule.guest_port <= 0 || rule.guest_port > 65535)
        return "Invalid guest port";

    const auto existing = active.find(rule.id);
    if (existing != active.end())
    {
        if (existing->second.guest_ip == guest_ip &&
            existing->second.rule.guest_port == rule.guest_port &&
            existing->second.rule.host_bind == rule.host_bind &&
            existing->second.rule.host_port == rule.host_port && existing->second.server &&
            existing->second.server->isListening())
        {
            return std::nullopt; // already active with same mapping
        }
        deactivate(rule.id);
    }

    auto server = std::make_unique<QTcpServer>(this);
    const QHostAddress address{QString::fromStdString(rule.host_bind)};
    if (address.isNull())
        return fmt::format("Invalid host bind address \"{}\"", rule.host_bind);

    if (!server->listen(address, static_cast<quint16>(rule.host_port)))
    {
        return fmt::format("Failed to listen on {}:{}: {}",
                           rule.host_bind,
                           rule.host_port,
                           server->errorString().toStdString());
    }

    auto* server_ptr = server.get();
    QObject::connect(server_ptr, &QTcpServer::newConnection, this, [this, id = rule.id]() {
        auto it = active.find(id);
        if (it == active.end() || !it->second.server)
            return;

        while (it->second.server->hasPendingConnections())
        {
            auto* client = it->second.server->nextPendingConnection();
            if (!client)
                continue;
            splice_connection(client, it->second.guest_ip, it->second.rule.guest_port);
        }
    });

    ActiveForward forward;
    forward.rule = rule;
    forward.guest_ip = guest_ip;
    forward.server = std::move(server);
    forward.status_message = fmt::format("Forwarding {}:{} → {}:{}",
                                         rule.host_bind,
                                         rule.host_port,
                                         guest_ip,
                                         rule.guest_port);
    active[rule.id] = std::move(forward);

    mpl::info(category,
              "Activated port forward {}:{} → {}:{} (instance {})",
              rule.host_bind,
              rule.host_port,
              guest_ip,
              rule.guest_port,
              rule.instance);
    return std::nullopt;
}

void mp::PortForwardManager::deactivate(const std::string& id)
{
    auto it = active.find(id);
    if (it == active.end())
        return;

    if (it->second.server)
        it->second.server->close();

    mpl::info(category,
              "Deactivated port forward {}:{} (instance {})",
              it->second.rule.host_bind,
              it->second.rule.host_port,
              it->second.rule.instance);
    active.erase(it);
}

void mp::PortForwardManager::deactivate_all_for(const std::string& instance)
{
    std::vector<std::string> ids;
    for (const auto& [id, forward] : active)
    {
        if (forward.rule.instance == instance)
            ids.push_back(id);
    }
    for (const auto& id : ids)
        deactivate(id);
}

void mp::PortForwardManager::deactivate_all()
{
    const auto ids = [this] {
        std::vector<std::string> out;
        out.reserve(active.size());
        for (const auto& [id, _] : active)
            out.push_back(id);
        return out;
    }();
    for (const auto& id : ids)
        deactivate(id);
}

bool mp::PortForwardManager::is_active(const std::string& id) const
{
    auto it = active.find(id);
    return it != active.end() && it->second.server && it->second.server->isListening();
}

mp::PortForwardManager::RuntimeStatus mp::PortForwardManager::status(const std::string& id) const
{
    RuntimeStatus out;
    auto it = active.find(id);
    if (it == active.end())
    {
        out.status_message = "Inactive";
        return out;
    }
    out.active = it->second.server && it->second.server->isListening();
    out.guest_ip = it->second.guest_ip;
    out.status_message = it->second.status_message;
    if (!out.active && out.status_message.empty())
        out.status_message = "Inactive";
    return out;
}

std::string mp::PortForwardManager::active_guest_ip(const std::string& id) const
{
    auto it = active.find(id);
    return it == active.end() ? std::string{} : it->second.guest_ip;
}

void mp::PortForwardManager::splice_connection(QTcpSocket* client,
                                               const std::string& guest_ip,
                                               int guest_port)
{
    client->setParent(this);

    auto* remote = new QTcpSocket(client);
    QObject::connect(client, &QTcpSocket::readyRead, remote, [client, remote]() {
        if (remote->state() == QAbstractSocket::ConnectedState)
            remote->write(client->readAll());
    });
    QObject::connect(remote, &QTcpSocket::readyRead, client, [client, remote]() {
        if (client->state() == QAbstractSocket::ConnectedState)
            client->write(remote->readAll());
    });

    const auto close_both = [client, remote]() {
        if (client->state() != QAbstractSocket::UnconnectedState)
            client->disconnectFromHost();
        if (remote->state() != QAbstractSocket::UnconnectedState)
            remote->disconnectFromHost();
        client->deleteLater();
    };

    QObject::connect(client, &QTcpSocket::disconnected, client, close_both);
    QObject::connect(remote, &QTcpSocket::disconnected, client, close_both);
    QObject::connect(remote,
                     &QAbstractSocket::errorOccurred,
                     client,
                     [client, remote, guest_ip, guest_port](QAbstractSocket::SocketError) {
                         mpl::debug(category,
                                    "Outbound connection to {}:{} failed: {}",
                                    guest_ip,
                                    guest_port,
                                    remote->errorString().toStdString());
                         client->disconnectFromHost();
                         client->deleteLater();
                     });

    remote->connectToHost(QString::fromStdString(guest_ip), static_cast<quint16>(guest_port));
}
