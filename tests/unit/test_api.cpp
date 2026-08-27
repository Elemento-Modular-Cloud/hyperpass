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

#include <multipass/constants.h>
#include <multipass/rpc/multipass.grpc.pb.h>

#include <boost/json.hpp>

#include <gmock/gmock.h>
#include <gtest/gtest.h>

namespace mp = multipass;
namespace mpt = multipass::test;
namespace api = multipass::api;

using namespace testing;

TEST(ApiAuth, publicPathsAreUnauthenticated)
{
    EXPECT_TRUE(api::is_public_path("/healthz"));
    EXPECT_TRUE(api::is_public_path("/readyz"));
    EXPECT_FALSE(api::is_public_path("/v1/instances"));
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
