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

#include "auth_middleware.h"
#include "config.h"
#include "handlers/handlers.h"
#include "multipass_discovery.h"
#include "operation_tracker.h"
#include "tls_fingerprint.h"
#include "vm_registry.h"

#include <multipass/constants.h>
#include <multipass/rpc/multipass.grpc.pb.h>

#include <boost/json.hpp>

#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include <filesystem>

namespace mp = multipass;
namespace mpt = multipass::test;
namespace api = multipass::api;

using namespace testing;

TEST(ApiAuth, publicPathsAreUnauthenticated)
{
    // AtomOS Service requires Bearer on / and /version; probes + fingerprint are public.
    EXPECT_FALSE(api::is_public_path("/"));
    EXPECT_FALSE(api::is_public_path("/version"));
    EXPECT_TRUE(api::is_public_path("/healthz"));
    EXPECT_TRUE(api::is_public_path("/readyz"));
    EXPECT_TRUE(api::is_public_path("/fingerprint"));
    EXPECT_TRUE(api::is_public_path("/api/v1/authenticate/cert"));
    EXPECT_FALSE(api::is_public_path("/api/v1.0/running"));
    EXPECT_FALSE(api::is_public_path("/api/v1.0/get_machine"));
    EXPECT_FALSE(api::is_public_path("/api/v1.0/create_machine"));
    EXPECT_FALSE(api::is_public_path("/api/v1.0/delete_machine"));
    EXPECT_FALSE(api::is_public_path("/v1/instances"));
}

TEST(ApiConfig, defaultListenAddressIsMatcherPort)
{
    EXPECT_EQ(mp::default_api_listen, "127.0.0.1:7777");
}

TEST(ApiAuth, insecureSkipsTokenCheck)
{
    api::ApiConfig config;
    config.insecure_no_auth = true;
    config.api_token = "secret";

    EXPECT_EQ(api::check_bearer_auth("", config), api::AuthResult::ok);
    EXPECT_EQ(api::check_bearer_auth("Bearer wrong", config), api::AuthResult::ok);
}

TEST(ApiAuth, missingAndInvalidTokensRejected)
{
    api::ApiConfig config;
    config.api_token = "secret";

    EXPECT_EQ(api::check_bearer_auth("", config), api::AuthResult::missing);
    EXPECT_EQ(api::check_bearer_auth("Basic secret", config), api::AuthResult::missing);
    EXPECT_EQ(api::check_bearer_auth("Bearer wrong", config), api::AuthResult::invalid);
    EXPECT_EQ(api::check_bearer_auth("Bearer secret", config), api::AuthResult::ok);
}

TEST(ApiAuth, errorBodyIsJson)
{
    const auto missing = api::auth_error_body(api::AuthResult::missing);
    const auto invalid = api::auth_error_body(api::AuthResult::invalid);
    EXPECT_THAT(missing, HasSubstr("missing_token"));
    EXPECT_THAT(invalid, HasSubstr("invalid_token"));
}

TEST(ApiTlsFingerprint, formatsSha256LikeAtomOS)
{
    // Empty DER → SHA-256 of empty input, colon-separated uppercase (AtomOS get_fingerprint).
    const auto fp = api::fingerprint_from_der("");
    EXPECT_EQ(fp,
              "E3:B0:C4:42:98:FC:1C:14:9A:FB:F4:C8:99:6F:B9:24:27:AE:41:E4:64:9B:93:4C:A4:95:99:1B:"
              "78:52:B8:55");
}

TEST(ApiTlsFingerprint, fetchRemoteAtomOSMatcherCert)
{
    // Live AtomOS matcher used as the Electros fingerprint reference host.
    const auto info = api::fetch_remote_tls_cert("172.16.25.197", api::atomos_matcher_tls_port);
    EXPECT_EQ(info.fingerprint,
              "46:59:75:6B:51:DE:E8:A0:3F:DB:41:0C:4C:D5:5B:82:B0:9A:E4:2A:5E:71:3F:26:59:9F:E1:A9:"
              "0C:B6:8C:28");
    EXPECT_FALSE(info.validated); // self-signed AtomOS cert
}

TEST(ApiTlsFingerprint, fetchRemoteMissingHostThrows)
{
    EXPECT_THROW(api::fetch_remote_tls_cert("", api::atomos_matcher_tls_port), std::runtime_error);
}

TEST(ApiConfig, parseListenAddressAcceptsHostPort)
{
    std::string host;
    int port = 0;
    api::parse_listen_address("127.0.0.1:51052", host, port);
    EXPECT_EQ(host, "127.0.0.1");
    EXPECT_EQ(port, 51052);
}

TEST(ApiConfig, parseListenAddressRejectsBadInput)
{
    std::string host;
    int port = 0;
    EXPECT_THROW(api::parse_listen_address("no-port", host, port), std::runtime_error);
    EXPECT_THROW(api::parse_listen_address(":51052", host, port), std::runtime_error);
    EXPECT_THROW(api::parse_listen_address("127.0.0.1:99999", host, port), std::runtime_error);
}

TEST(ApiOperationTracker, startUpdateAndGet)
{
    api::OperationTracker tracker;
    const auto id = tracker.start("launch", "starting");
    ASSERT_FALSE(id.empty());

    auto op = tracker.get(id);
    ASSERT_TRUE(op.has_value());
    EXPECT_EQ(op->kind, "launch");
    EXPECT_EQ(op->state, api::OperationState::pending);

    EXPECT_TRUE(tracker.update(id, api::OperationState::running, "pulling image"));
    op = tracker.get(id);
    ASSERT_TRUE(op.has_value());
    EXPECT_EQ(op->state, api::OperationState::running);
    EXPECT_EQ(op->message, "pulling image");

    EXPECT_TRUE(tracker.succeed(id, "done"));
    op = tracker.get(id);
    ASSERT_TRUE(op.has_value());
    EXPECT_EQ(op->state, api::OperationState::succeeded);

    EXPECT_FALSE(tracker.get("missing").has_value());
}

TEST(ApiOperationTracker, failSetsError)
{
    api::OperationTracker tracker;
    const auto id = tracker.start("launch");
    EXPECT_TRUE(tracker.fail(id, "boom"));
    const auto op = tracker.get(id);
    ASSERT_TRUE(op.has_value());
    EXPECT_EQ(op->state, api::OperationState::failed);
    EXPECT_EQ(op->error, "boom");
}

TEST(ApiHandlers, listReplyToJsonMapsInstances)
{
    mp::ListReply reply;
    auto* instances = reply.mutable_instance_list();
    auto* item = instances->add_instances();
    item->set_name("primary");
    item->mutable_instance_status()->set_status(mp::InstanceStatus::RUNNING);
    item->set_current_release("24.04");
    item->add_ipv4("10.0.2.15");

    const auto json = api::list_reply_to_json(reply, mp::instance_source_hyperpass);
    EXPECT_THAT(json, HasSubstr("\"name\":\"primary\""));
    EXPECT_THAT(json, HasSubstr("\"source\":\"hyperpass\""));
    EXPECT_THAT(json, HasSubstr("\"state\":\"running\""));
    EXPECT_THAT(json, HasSubstr("10.0.2.15"));
}

TEST(ApiHandlers, appendInstancesTagsSource)
{
    mp::ListReply hp;
    auto* hp_item = hp.mutable_instance_list()->add_instances();
    hp_item->set_name("hp-vm");
    hp_item->mutable_instance_status()->set_status(mp::InstanceStatus::STOPPED);

    mp::ListReply mp_reply;
    auto* mp_item = mp_reply.mutable_instance_list()->add_instances();
    mp_item->set_name("mp-vm");
    mp_item->mutable_instance_status()->set_status(mp::InstanceStatus::RUNNING);

    boost::json::array out;
    api::append_instances_from_reply(out, hp, mp::instance_source_hyperpass);
    api::append_instances_from_reply(out, mp_reply, mp::instance_source_multipass);

    ASSERT_EQ(out.size(), 2);
    EXPECT_EQ(out[0].as_object().at("name").as_string(), "hp-vm");
    EXPECT_EQ(out[0].as_object().at("source").as_string(), "hyperpass");
    EXPECT_EQ(out[1].as_object().at("name").as_string(), "mp-vm");
    EXPECT_EQ(out[1].as_object().at("source").as_string(), "multipass");
}

TEST(ApiHandlers, operationToJsonIncludesState)
{
    api::Operation op;
    op.id = "op-1";
    op.kind = "launch";
    op.state = api::OperationState::running;
    op.message = "working";

    const auto json = api::operation_to_json(op);
    EXPECT_THAT(json, HasSubstr("\"id\":\"op-1\""));
    EXPECT_THAT(json, HasSubstr("\"state\":\"running\""));
    EXPECT_THAT(json, HasSubstr("working"));
}

TEST(ApiDiscovery, defaultMultipassAddressIsPlatformSpecific)
{
    const auto address = api::default_multipass_server_address();
    EXPECT_FALSE(address.empty());
#if defined(MULTIPASS_PLATFORM_WINDOWS)
    EXPECT_EQ(address, "localhost:50051");
#elif defined(MULTIPASS_PLATFORM_APPLE)
    EXPECT_EQ(address, "unix:/var/run/multipass_socket");
#else
    EXPECT_THAT(address, HasSubstr("multipass_socket"));
#endif
}

TEST(ApiVmRegistry, upsertFindAndListByClient)
{
    const auto path =
        (std::filesystem::temp_directory_path() / "hyperpass-api-registry-test.json").string();
    std::filesystem::remove(path);

    api::VmRegistry registry{path};
    api::RegisteredVm vm;
    vm.vm_uid = "uid-1";
    vm.vm_name = "web-1";
    vm.client_uid = "client-a";
    vm.os_family = "linux";
    vm.os_flavour = "ubuntu";
    registry.upsert(vm);

    auto found = registry.find_by_uid("uid-1");
    ASSERT_TRUE(found.has_value());
    EXPECT_EQ(found->vm_name, "web-1");

    const auto for_client = registry.list_for_client("client-a");
    ASSERT_EQ(for_client.size(), 1u);
    EXPECT_EQ(for_client[0].vm_uid, "uid-1");
    EXPECT_TRUE(registry.list_for_client("other").empty());

    EXPECT_TRUE(registry.remove("uid-1"));
    EXPECT_FALSE(registry.find_by_uid("uid-1").has_value());

    // Reload from disk after remove
    api::VmRegistry reloaded{path};
    EXPECT_FALSE(reloaded.find_by_uid("uid-1").has_value());
    std::filesystem::remove(path);
}
