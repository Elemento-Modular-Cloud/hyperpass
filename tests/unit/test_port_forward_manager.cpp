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

#include "common.h"

#include <src/daemon/port_forward_manager.h>

#include <QEventLoop>
#include <QHostAddress>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>

namespace mp = multipass;
namespace mpt = multipass::test;
using namespace testing;

namespace
{
quint16 pick_free_port()
{
    QTcpServer probe;
    if (!probe.listen(QHostAddress::LocalHost, 0))
        throw std::runtime_error("failed to pick free port");
    const auto port = probe.serverPort();
    probe.close();
    return port;
}

bool wait_for(std::chrono::milliseconds timeout, const std::function<bool()>& ready)
{
    QEventLoop loop;
    QTimer timer;
    timer.setSingleShot(true);
    QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);

    QTimer poll;
    poll.setInterval(10);
    QObject::connect(&poll, &QTimer::timeout, &loop, [&] {
        if (ready())
            loop.quit();
    });

    timer.start(timeout);
    poll.start();
    loop.exec();
    return ready();
}
} // namespace

TEST(PortForwardManager, activatesAndSplicesToGuest)
{
    QTcpServer backend;
    ASSERT_TRUE(backend.listen(QHostAddress::LocalHost, 0));
    const auto guest_port = backend.serverPort();

    QByteArray received;
    QObject::connect(&backend, &QTcpServer::newConnection, &backend, [&] {
        auto* sock = backend.nextPendingConnection();
        QObject::connect(sock, &QTcpSocket::readyRead, sock, [sock, &received] {
            received.append(sock->readAll());
            sock->write("pong");
            sock->flush();
        });
    });

    mp::PortForwardManager manager;
    mp::PortForwardRule rule;
    rule.id = "fwd-1";
    rule.instance = "vm1";
    rule.host_bind = "127.0.0.1";
    rule.host_port = static_cast<int>(pick_free_port());
    rule.guest_port = static_cast<int>(guest_port);

    ASSERT_FALSE(manager.activate(rule, "127.0.0.1").has_value());
    EXPECT_TRUE(manager.is_active(rule.id));

    QTcpSocket client;
    client.connectToHost(QHostAddress::LocalHost, static_cast<quint16>(rule.host_port));
    ASSERT_TRUE(wait_for(std::chrono::seconds{2},
                         [&] { return client.state() == QAbstractSocket::ConnectedState; }));
    client.write("ping");
    client.flush();

    ASSERT_TRUE(wait_for(std::chrono::seconds{2}, [&] { return received == "ping"; }));
    ASSERT_TRUE(wait_for(std::chrono::seconds{2}, [&] { return client.bytesAvailable() > 0; }));
    EXPECT_EQ(client.readAll(), QByteArray{"pong"});

    manager.deactivate(rule.id);
    EXPECT_FALSE(manager.is_active(rule.id));
}

TEST(PortForwardManager, rejectsEmptyGuestIp)
{
    mp::PortForwardManager manager;
    mp::PortForwardRule rule;
    rule.id = "fwd-empty";
    rule.instance = "vm1";
    rule.host_bind = "127.0.0.1";
    rule.host_port = 18080;
    rule.guest_port = 80;

    auto err = manager.activate(rule, "");
    ASSERT_TRUE(err.has_value());
    EXPECT_THAT(*err, HasSubstr("unavailable"));
}

TEST(PortForwardManager, rebindsWhenGuestIpChanges)
{
    mp::PortForwardManager manager;
    mp::PortForwardRule rule;
    rule.id = "fwd-rebind";
    rule.instance = "vm1";
    rule.host_bind = "127.0.0.1";
    rule.host_port = static_cast<int>(pick_free_port());
    rule.guest_port = 9;

    ASSERT_FALSE(manager.activate(rule, "127.0.0.1").has_value());
    EXPECT_EQ(manager.active_guest_ip(rule.id), "127.0.0.1");

    ASSERT_FALSE(manager.activate(rule, "127.0.0.2").has_value());
    EXPECT_EQ(manager.active_guest_ip(rule.id), "127.0.0.2");
    EXPECT_TRUE(manager.is_active(rule.id));

    manager.deactivate_all_for("vm1");
    EXPECT_FALSE(manager.is_active(rule.id));
}

TEST(PortForwardManager, activateSameMappingIsIdempotent)
{
    mp::PortForwardManager manager;
    mp::PortForwardRule rule;
    rule.id = "fwd-idem";
    rule.instance = "vm1";
    rule.host_bind = "127.0.0.1";
    rule.host_port = static_cast<int>(pick_free_port());
    rule.guest_port = 22;

    ASSERT_FALSE(manager.activate(rule, "127.0.0.1").has_value());
    ASSERT_FALSE(manager.activate(rule, "127.0.0.1").has_value());
    EXPECT_TRUE(manager.is_active(rule.id));
    manager.deactivate(rule.id);
}
