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

#include "daemon_test_fixture.h"

#include "common.h"
#include "mock_permission_utils.h"
#include "mock_platform.h"
#include "mock_server_reader_writer.h"
#include "mock_settings.h"
#include "mock_virtual_machine.h"
#include "mock_vm_image_vault.h"

#include <src/daemon/daemon.h>

#include <multipass/ip_address.h>

#include <QHostAddress>
#include <QTcpServer>

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
} // namespace

struct TestDaemonPortForward : public mpt::DaemonTestFixture
{
    void SetUp() override
    {
        EXPECT_CALL(mock_settings, register_handler).WillRepeatedly(Return(nullptr));
        EXPECT_CALL(mock_settings, unregister_handler).Times(AnyNumber());
        EXPECT_CALL(mock_settings, get(Eq(mp::mounts_key))).WillRepeatedly(Return("true"));
        mpt::expect_default_host_resource_settings(mock_settings);
    }

    const std::string mock_instance_name{"real-zebraphant"};
    const std::string mac_addr{"52:54:00:73:76:28"};
    std::vector<mp::NetworkInterface> extra_interfaces;

    mpt::MockPlatform::GuardedMock attr{mpt::MockPlatform::inject<NiceMock>()};
    mpt::MockPlatform* mock_platform = attr.first;

    mpt::MockSettings::GuardedMock mock_settings_injection =
        mpt::MockSettings::inject<StrictMock>();
    mpt::MockSettings& mock_settings = *mock_settings_injection.first;

    const mpt::MockPermissionUtils::GuardedMock mock_permission_utils_injection =
        mpt::MockPermissionUtils::inject<NiceMock>();
    mpt::MockPermissionUtils& mock_permission_utils = *mock_permission_utils_injection.first;
};

TEST_F(TestDaemonPortForward, addListRemoveRoundTrip)
{
    auto mock_factory = use_a_mock_vm_factory();
    const auto [temp_dir, filename] =
        plant_instance_json(fake_json_contents(mac_addr, extra_interfaces));

    auto instance_ptr = std::make_unique<NiceMock<mpt::MockVirtualMachine>>();
    EXPECT_CALL(*mock_factory, create_virtual_machine).WillOnce([&instance_ptr](auto&&...) {
        return std::move(instance_ptr);
    });
    EXPECT_CALL(*instance_ptr, get_name).WillRepeatedly(ReturnRef(mock_instance_name));
    EXPECT_CALL(*instance_ptr, current_state())
        .WillRepeatedly(Return(mp::VirtualMachine::State::running));
    EXPECT_CALL(*instance_ptr, management_ipv4)
        .WillRepeatedly(Return(mp::IPAddress{"192.168.67.10"}));

    config_builder.data_directory = temp_dir->path();
    config_builder.vault = std::make_unique<NiceMock<mpt::MockVMImageVault>>();

    mp::Daemon daemon{config_builder.build()};

    const auto host_port = static_cast<int>(pick_free_port());

    mp::AddPortForwardRequest add_request;
    add_request.set_instance(mock_instance_name);
    add_request.set_host_port(host_port);
    add_request.set_guest_port(443);
    add_request.set_host_bind("127.0.0.1");

    std::string forward_id;
    {
        StrictMock<mpt::MockServerReaderWriter<mp::AddPortForwardReply, mp::AddPortForwardRequest>>
            mock_server{};
        EXPECT_CALL(mock_server, Write(_, _))
            .WillOnce([&](const mp::AddPortForwardReply& reply, auto) {
                EXPECT_FALSE(reply.forward().id().empty());
                EXPECT_EQ(reply.forward().host_port(), host_port);
                EXPECT_EQ(reply.forward().guest_port(), 443);
                forward_id = reply.forward().id();
                return true;
            });

        auto status =
            call_daemon_slot(daemon, &mp::Daemon::add_port_forward, add_request, mock_server);
        EXPECT_TRUE(status.ok());
    }

    {
        mp::AddPortForwardRequest collision = add_request;
        StrictMock<mpt::MockServerReaderWriter<mp::AddPortForwardReply, mp::AddPortForwardRequest>>
            mock_server{};
        auto status =
            call_daemon_slot(daemon, &mp::Daemon::add_port_forward, collision, mock_server);
        EXPECT_EQ(status.error_code(), grpc::StatusCode::ALREADY_EXISTS);
    }

    {
        mp::ListPortForwardsRequest list_request;
        list_request.set_instance(mock_instance_name);
        StrictMock<
            mpt::MockServerReaderWriter<mp::ListPortForwardsReply, mp::ListPortForwardsRequest>>
            mock_server{};
        EXPECT_CALL(mock_server, Write(_, _))
            .WillOnce([&](const mp::ListPortForwardsReply& reply, auto) {
                EXPECT_EQ(reply.forwards_size(), 1);
                if (reply.forwards_size() == 1)
                {
                    EXPECT_EQ(reply.forwards(0).id(), forward_id);
                    EXPECT_TRUE(reply.forwards(0).active());
                    EXPECT_EQ(reply.forwards(0).guest_ip(), "192.168.67.10");
                }
                return true;
            });

        auto status =
            call_daemon_slot(daemon, &mp::Daemon::list_port_forwards, list_request, mock_server);
        EXPECT_TRUE(status.ok());
    }

    {
        mp::RemovePortForwardRequest remove_request;
        remove_request.set_id(forward_id);
        StrictMock<
            mpt::MockServerReaderWriter<mp::RemovePortForwardReply, mp::RemovePortForwardRequest>>
            mock_server{};
        EXPECT_CALL(mock_server, Write(_, _)).Times(1);

        auto status =
            call_daemon_slot(daemon, &mp::Daemon::remove_port_forward, remove_request, mock_server);
        EXPECT_TRUE(status.ok());
    }

    {
        mp::ListPortForwardsRequest list_request;
        StrictMock<
            mpt::MockServerReaderWriter<mp::ListPortForwardsReply, mp::ListPortForwardsRequest>>
            mock_server{};
        EXPECT_CALL(mock_server, Write(_, _))
            .WillOnce([](const mp::ListPortForwardsReply& reply, auto) {
                EXPECT_EQ(reply.forwards_size(), 0);
                return true;
            });

        auto status =
            call_daemon_slot(daemon, &mp::Daemon::list_port_forwards, list_request, mock_server);
        EXPECT_TRUE(status.ok());
    }
}

TEST_F(TestDaemonPortForward, addWithoutGuestIpStillPersistsInactive)
{
    auto mock_factory = use_a_mock_vm_factory();
    const auto [temp_dir, filename] =
        plant_instance_json(fake_json_contents(mac_addr, extra_interfaces));

    auto instance_ptr = std::make_unique<NiceMock<mpt::MockVirtualMachine>>();
    EXPECT_CALL(*mock_factory, create_virtual_machine).WillOnce([&instance_ptr](auto&&...) {
        return std::move(instance_ptr);
    });
    EXPECT_CALL(*instance_ptr, get_name).WillRepeatedly(ReturnRef(mock_instance_name));
    EXPECT_CALL(*instance_ptr, current_state())
        .WillRepeatedly(Return(mp::VirtualMachine::State::stopped));
    EXPECT_CALL(*instance_ptr, management_ipv4)
        .WillRepeatedly(Return(std::optional<mp::IPAddress>{}));

    config_builder.data_directory = temp_dir->path();
    config_builder.vault = std::make_unique<NiceMock<mpt::MockVMImageVault>>();

    mp::Daemon daemon{config_builder.build()};

    const auto host_port = static_cast<int>(pick_free_port());
    mp::AddPortForwardRequest add_request;
    add_request.set_instance(mock_instance_name);
    add_request.set_host_port(host_port);
    add_request.set_guest_port(80);

    StrictMock<mpt::MockServerReaderWriter<mp::AddPortForwardReply, mp::AddPortForwardRequest>>
        mock_server{};
    EXPECT_CALL(mock_server, Write(_, _))
        .WillOnce([](const mp::AddPortForwardReply& reply, auto) {
            EXPECT_FALSE(reply.forward().active());
            EXPECT_FALSE(reply.forward().id().empty());
            return true;
        });

    auto status = call_daemon_slot(daemon, &mp::Daemon::add_port_forward, add_request, mock_server);
    EXPECT_TRUE(status.ok());
}
