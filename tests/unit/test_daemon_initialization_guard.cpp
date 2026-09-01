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

#include "daemon_test_fixture.h"

#include "common.h"
#include "mock_permission_utils.h"
#include "mock_platform.h"
#include "mock_server_reader_writer.h"
#include "mock_settings.h"
#include "mock_virtual_machine.h"
#include "mock_vm_image_vault.h"

#include <src/daemon/daemon.h>

#include <multipass/constants.h>
#include <multipass/format.h>

namespace mp = multipass;
namespace mpt = multipass::test;
using namespace testing;

struct TestDaemonInitializationGuard : public mpt::DaemonTestFixture
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

    mpt::MockSettings::GuardedMock mock_settings_injection =
        mpt::MockSettings::inject<StrictMock>();
    mpt::MockSettings& mock_settings = *mock_settings_injection.first;

    const mpt::MockPermissionUtils::GuardedMock mock_permission_utils_injection =
        mpt::MockPermissionUtils::inject<NiceMock>();
};

TEST_F(TestDaemonInitializationGuard, sshInfoRejectsStartingInstance)
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
        .WillRepeatedly(Return(mp::VirtualMachine::State::starting));

    config_builder.data_directory = temp_dir->path();
    config_builder.vault = std::make_unique<NiceMock<mpt::MockVMImageVault>>();

    mp::Daemon daemon{config_builder.build()};

    mp::SSHInfoRequest request;
    request.add_instance_name(mock_instance_name);

    StrictMock<mpt::MockServerReaderWriter<mp::SSHInfoReply, mp::SSHInfoRequest>> mock_server;

    auto status = call_daemon_slot(daemon, &mp::Daemon::ssh_info, request, std::move(mock_server));

    EXPECT_EQ(status.error_code(), grpc::StatusCode::FAILED_PRECONDITION);
    EXPECT_THAT(status.error_message(), HasSubstr("still initializing"));
}

TEST_F(TestDaemonInitializationGuard, sshInfoAllowsRunningInstance)
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

    config_builder.data_directory = temp_dir->path();
    config_builder.vault = std::make_unique<NiceMock<mpt::MockVMImageVault>>();

    mp::Daemon daemon{config_builder.build()};

    mp::SSHInfoRequest request;
    request.add_instance_name(mock_instance_name);

    StrictMock<mpt::MockServerReaderWriter<mp::SSHInfoReply, mp::SSHInfoRequest>> mock_server;
    EXPECT_CALL(mock_server, Write(_, _)).Times(1);

    auto status = call_daemon_slot(daemon, &mp::Daemon::ssh_info, request, std::move(mock_server));

    EXPECT_TRUE(status.ok());
}

TEST_F(TestDaemonInitializationGuard, startRejectsAlreadyStartingInstance)
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
        .WillRepeatedly(Return(mp::VirtualMachine::State::starting));
    EXPECT_CALL(*instance_ptr, start()).Times(0);
    EXPECT_CALL(*instance_ptr, wait_until_ssh_up(_)).Times(0);

    config_builder.data_directory = temp_dir->path();
    config_builder.vault = std::make_unique<NiceMock<mpt::MockVMImageVault>>();

    mp::Daemon daemon{config_builder.build()};

    mp::StartRequest request;
    request.mutable_instance_names()->add_instance_name(mock_instance_name);

    StrictMock<mpt::MockServerReaderWriter<mp::StartReply, mp::StartRequest>> mock_server;

    auto status = call_daemon_slot(daemon, &mp::Daemon::start, request, std::move(mock_server));

    EXPECT_FALSE(status.ok());
    EXPECT_THAT(status.error_message(), HasSubstr("still initializing"));
}
