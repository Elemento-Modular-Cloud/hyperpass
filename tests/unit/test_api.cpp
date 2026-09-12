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
#include "https_certs.h"
#include "marketplace_cloud_init.h"
#include "multipass_discovery.h"
#include "operation_tracker.h"
#include "spot_spec.h"
#include "tls_fingerprint.h"
#include "vm_registry.h"

#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/rpc/multipass.grpc.pb.h>

#include "mock_logger.h"
#include "temp_dir.h"

#include <boost/json.hpp>

#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include <gmock/gmock.h>
#include <gtest/gtest.h>

#include <openssl/pem.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

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
    EXPECT_TRUE(api::is_public_path("/ca.crt"));
    EXPECT_TRUE(api::is_public_path("/api/v1/authenticate/cert"));
    EXPECT_FALSE(api::is_public_path("/api/v1.0/running"));
    EXPECT_FALSE(api::is_public_path("/api/v1.0/register"));
    EXPECT_FALSE(api::is_public_path("/api/v1.0/unregister"));
    EXPECT_FALSE(api::is_public_path("/api/v1.0/credentials/abc"));
    EXPECT_FALSE(api::is_public_path("/v1/instances"));
    EXPECT_FALSE(api::is_public_path("/v1/chat/completions"));
    EXPECT_TRUE(api::is_openai_inference_path("/v1/chat/completions"));
    EXPECT_TRUE(api::is_openai_inference_path("/v1/models"));
    EXPECT_FALSE(api::is_openai_inference_path("/v1/instances"));
    EXPECT_FALSE(api::is_openai_inference_path("/api/v1.0/models"));
}

TEST(ApiConfig, defaultListenAddressIsLocalhostAndVmGateway)
{
    EXPECT_EQ(mp::default_api_vm_gateway, "192.168.67.1");
    EXPECT_EQ(mp::default_api_listen, "127.0.0.1,192.168.67.1:7777");
}

TEST(ApiConfig, parseListenEndpointAcceptsMultipleHosts)
{
    const auto endpoint = api::parse_listen_endpoint("127.0.0.1,192.168.67.1:7777");
    ASSERT_EQ(endpoint.hosts.size(), 2);
    EXPECT_EQ(endpoint.hosts[0], "127.0.0.1");
    EXPECT_EQ(endpoint.hosts[1], "192.168.67.1");
    EXPECT_EQ(endpoint.port, 7777);
}

TEST(ApiConfig, parseListenEndpointStripsSchemeAndWhitespace)
{
    const auto endpoint = api::parse_listen_endpoint("https://127.0.0.1, 192.168.67.1:7777");
    ASSERT_EQ(endpoint.hosts.size(), 2);
    EXPECT_EQ(endpoint.hosts[0], "127.0.0.1");
    EXPECT_EQ(endpoint.hosts[1], "192.168.67.1");
    EXPECT_EQ(endpoint.port, 7777);
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

    const auto json = api::list_reply_to_json(reply, mp::instance_source_elp);
    EXPECT_THAT(json, HasSubstr("\"name\":\"primary\""));
    EXPECT_THAT(json, HasSubstr("\"source\":\"elp\""));
    EXPECT_THAT(json, HasSubstr("\"state\":\"running\""));
    EXPECT_THAT(json, HasSubstr("10.0.2.15"));
}

TEST(ApiHandlers, appendInstancesTagsSource)
{
    mp::ListReply hp;
    auto* hp_item = hp.mutable_instance_list()->add_instances();
    hp_item->set_name("elp-vm");
    hp_item->mutable_instance_status()->set_status(mp::InstanceStatus::STOPPED);

    mp::ListReply mp_reply;
    auto* mp_item = mp_reply.mutable_instance_list()->add_instances();
    mp_item->set_name("mp-vm");
    mp_item->mutable_instance_status()->set_status(mp::InstanceStatus::RUNNING);

    boost::json::array out;
    api::append_instances_from_reply(out, hp, mp::instance_source_elp);
    api::append_instances_from_reply(out, mp_reply, mp::instance_source_multipass);

    ASSERT_EQ(out.size(), 2);
    EXPECT_EQ(out[0].as_object().at("name").as_string(), "elp-vm");
    EXPECT_EQ(out[0].as_object().at("source").as_string(), "elp");
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

TEST(ApiVmRegistry, upsertFindAndList)
{
    const auto path =
        (std::filesystem::temp_directory_path() / "elp-api-registry-test.json").string();
    std::filesystem::remove(path);

    api::VmRegistry registry{path};
    api::RegisteredVm vm;
    vm.vm_uid = "uid-1";
    vm.vm_name = "web-1";
    vm.username = "elemento";
    vm.region = "local";
    vm.template_id = "n8n";
    vm.service_id = "n8n";
    vm.spec_json = R"({"vm_name":"web-1","tags":["service:n8n"]})";
    registry.upsert(vm);

    auto found = registry.find_by_uid("uid-1");
    ASSERT_TRUE(found.has_value());
    EXPECT_EQ(found->vm_name, "web-1");
    EXPECT_EQ(found->service_id, "n8n");
    EXPECT_EQ(found->source, "elp");
    EXPECT_EQ(api::normalize_vm_source(""), "elp");
    EXPECT_EQ(api::normalize_vm_source("multipass"), "multipass");

    const auto all = registry.all();
    ASSERT_EQ(all.size(), 1u);
    EXPECT_EQ(all[0].vm_uid, "uid-1");

    api::RegisteredVm mp_vm;
    mp_vm.vm_uid = "uid-mp";
    mp_vm.vm_name = "web-1";
    mp_vm.source = "multipass";
    registry.upsert(mp_vm);
    auto elp_named = registry.find_by_name("web-1", mp::instance_source_elp);
    auto mp_named = registry.find_by_name("web-1", mp::instance_source_multipass);
    ASSERT_TRUE(elp_named.has_value());
    ASSERT_TRUE(mp_named.has_value());
    EXPECT_EQ(elp_named->vm_uid, "uid-1");
    EXPECT_EQ(mp_named->vm_uid, "uid-mp");

    EXPECT_TRUE(registry.remove("uid-1"));
    EXPECT_TRUE(registry.remove("uid-mp"));
    EXPECT_FALSE(registry.find_by_uid("uid-1").has_value());

    api::VmRegistry reloaded{path};
    EXPECT_FALSE(reloaded.find_by_uid("uid-1").has_value());
    std::filesystem::remove(path);
}

namespace
{
constexpr auto spot_basic = R"({
  "vm_name": "web-1",
  "cpu": {"slots": 2, "shared_cores": true, "arch": ["X86_64"]},
  "mem": {"capacity_mb": 4096},
  "os": {"family": "linux", "flavour": "ubuntu", "version": "24.04"},
  "storage": {"boot": {"name": "root", "size_gb": 32}, "data": []},
  "pci": {"devices": []},
  "networks": [{"kind": "natted"}],
  "auth": {"username": "elemento", "password": "secret", "ssh_key": "ssh-rsa AAAA"},
  "tags": [],
  "cloud_init_b64": "I2Nsb3VkLWNvbmZpZwpwYWNrYWdlczoKICAtIG5naW54Cg=="
})";
}

TEST(ApiSpotSpec, parsesRegisterAndMapsLaunch)
{
    const auto spec = api::parse_spot_spec(spot_basic, api::SpotParseMode::register_vm);
    EXPECT_EQ(spec.vm_name, "web-1");
    EXPECT_EQ(spec.cpu.slot_count, 2);
    EXPECT_EQ(spec.mem.capacity_mb, 4096);
    EXPECT_EQ(spec.os.version, "24.04");
    EXPECT_EQ(spec.storage.boot.size_gb, 32);
    EXPECT_TRUE(spec.has_cloud_init_b64);
    EXPECT_EQ(spec.auth.username, "elemento");
    EXPECT_TRUE(spec.networks.size() == 1);
    EXPECT_EQ(spec.networks[0].kind, "natted");

    const auto decoded = api::decode_cloud_init_b64(spec.cloud_init_b64);
    EXPECT_THAT(decoded, HasSubstr("#cloud-config"));

    const auto launch = api::launch_spec_from_spot(spec, decoded);
    EXPECT_EQ(launch.instance_name, "web-1");
    EXPECT_EQ(launch.image, "24.04");
    EXPECT_EQ(launch.num_cores, 2);
    EXPECT_EQ(launch.mem_size, "4096M");
    EXPECT_EQ(launch.disk_space, "32G");
    EXPECT_TRUE(launch.service_id.empty());
}

TEST(ApiSpotSpec, templateWinsOverB64AndSetsServiceId)
{
    const auto body = R"({
      "vm_name": "n8n",
      "cpu": {"slots": 4, "shared_cores": true, "arch": ["X86_64"]},
      "mem": {"capacity_mb": 4096},
      "os": {"family": "linux", "flavour": "ubuntu", "version": "24.04"},
      "storage": {"boot": {"name": "root", "size_gb": 32}, "data": []},
      "networks": [{"kind": "public", "open_ports": [{"protocol": "tcp", "port": 5678}]}],
      "auth": {"username": "elemento"},
      "tags": ["service:n8n"],
      "startup": {"kind": "cloud-init", "template": "n8n"},
      "cloud_init_b64": "I2Nsb3VkLWNvbmZpZwpwYWNrYWdlczoKICAtIG5naW54Cg=="
    })";
    const auto spec = api::parse_spot_spec(body, api::SpotParseMode::register_vm);
    EXPECT_EQ(spec.startup_template, "n8n");
    EXPECT_EQ(api::service_id_from_spec(spec), "n8n");
    EXPECT_EQ(api::first_open_port(spec), 5678);

    const auto public_json = api::spec_to_public_json(spec);
    EXPECT_FALSE(public_json.contains("auth"));
    EXPECT_FALSE(public_json.contains("cloud_init_b64"));
    EXPECT_EQ(public_json.at("startup").as_object().at("template").as_string(), "n8n");
}

TEST(ApiSpotSpec, canallocateDropsIdentityAndTemplate)
{
    const auto spec = api::parse_spot_spec(spot_basic, api::SpotParseMode::canallocate);
    EXPECT_TRUE(spec.auth.username.empty());
    EXPECT_TRUE(spec.startup_template.empty());
    EXPECT_FALSE(spec.has_cloud_init_b64);
    EXPECT_EQ(spec.mem.capacity_mb, 4096);
    EXPECT_TRUE(api::can_place_spot(spec, 8192, 8));
    EXPECT_FALSE(api::can_place_spot(spec, 1024, 8));
    EXPECT_FALSE(api::can_place_spot(spec, 8192, 1));
}

TEST(ApiSpotSpec, canallocateEmptyBodyMeansAnyRemainingRam)
{
    const auto spec = api::parse_spot_spec("", api::SpotParseMode::canallocate);
    EXPECT_EQ(spec.mem.capacity_mb, 0);
    EXPECT_TRUE(api::can_allocate_from_available(1024, spec.mem.capacity_mb));
    EXPECT_FALSE(api::can_allocate_from_available(0, spec.mem.capacity_mb));
}

TEST(ApiSpotSpec, tagWithoutTemplateSetsServiceId)
{
    const auto body = R"({
      "vm_name": "svc",
      "cpu": {"slots": 2, "shared_cores": true, "arch": ["X86_64"]},
      "mem": {"capacity_mb": 2048},
      "os": {"family": "linux", "flavour": "ubuntu"},
      "storage": {"boot": {"name": "root", "size_gb": 16}},
      "tags": ["service:openclaw"]
    })";
    const auto spec = api::parse_spot_spec(body, api::SpotParseMode::register_vm);
    EXPECT_EQ(api::service_id_from_spec(spec), "openclaw");
}

TEST(ApiSpotSpec, defaultsNattedNicWhenNetworksOmitted)
{
    const auto body = R"({
      "vm_name": "plain",
      "cpu": {"slots": 1, "shared_cores": true, "arch": ["X86_64"]},
      "mem": {"capacity_mb": 1024},
      "os": {"family": "linux", "flavour": "debian"},
      "storage": {"boot": {"name": "root", "size_gb": 8}}
    })";
    const auto spec = api::parse_spot_spec(body, api::SpotParseMode::register_vm);
    ASSERT_EQ(spec.networks.size(), 1u);
    EXPECT_EQ(spec.networks[0].kind, "natted");
    const auto launch = api::launch_spec_from_spot(spec, {});
    EXPECT_EQ(launch.image, "debian");
}

TEST(ApiSpotSpec, synthesizesFromDaemonListFields)
{
    const auto spec = api::spec_from_daemon_fields("gui-n8n", "Ubuntu 24.04.3 LTS", "Ubuntu", "n8n");
    EXPECT_EQ(spec.vm_name, "gui-n8n");
    EXPECT_EQ(spec.os.family, "ubuntu");
    EXPECT_EQ(spec.os.version, "24.04");
    EXPECT_EQ(spec.startup_template, "n8n");
    ASSERT_EQ(spec.tags.size(), 1u);
    EXPECT_EQ(spec.tags[0], "service:n8n");
    ASSERT_EQ(spec.networks.size(), 1u);
    EXPECT_EQ(spec.networks[0].kind, "natted");

    const auto public_json = api::spec_to_public_json(spec);
    EXPECT_EQ(public_json.at("startup").as_object().at("template").as_string(), "n8n");
}

TEST(ApiMarketplace, lookupPinnedAndFamilyThenRender)
{
    mpt::TempDir temp_dir;
    const QString services = temp_dir.path() + "/services";
    std::filesystem::create_directories((services + "/n8n_v2").toStdString());
    std::filesystem::create_directories((services + "/n8n_v3").toStdString());

    auto write = [](const QString& path, std::string_view body) {
        std::ofstream out{path.toStdString()};
        out << body;
    };
    write(services + "/n8n_v2/service.yaml",
          "metadata:\n  version: \"2\"\ncloud_init:\n  entrypoint: cloud-init.yaml\n"
          "files: []\nprerequisites:\n  firewall:\n    - port: 5678\n      direction: ingress\n");
    write(services + "/n8n_v2/cloud-init.yaml", "#cloud-config\npackages:\n  - old\n");
    write(services + "/n8n_v3/service.yaml",
          "metadata:\n  version: \"3\"\ncloud_init:\n  entrypoint: cloud-init.yaml\n"
          "files:\n  - source: note.txt\n    destination: /opt/note.txt\n    owner: root:root\n"
          "    permissions: \"0644\"\n"
          "prerequisites:\n  firewall:\n    - port: 5678\n      direction: ingress\n");
    write(services + "/n8n_v3/cloud-init.yaml", "#cloud-config\npackages:\n  - n8n\n");
    write(services + "/n8n_v3/note.txt", "hello\n");

    ::setenv("ELP_MARKETPLACE_DIR", temp_dir.path().toUtf8().constData(), 1);
    ::unsetenv("ELP_MARKETPLACE_URL");

    const auto library = api::load_marketplace_library();
    const auto* pinned = library.lookup("n8n_v2");
    ASSERT_NE(pinned, nullptr);
    EXPECT_EQ(pinned->id, "n8n_v2");
    const auto* latest = library.lookup("n8n");
    ASSERT_NE(latest, nullptr);
    EXPECT_EQ(latest->id, "n8n_v3");

    const auto rendered = api::render_marketplace_cloud_init(
        *latest, "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n");
    EXPECT_THAT(rendered, HasSubstr("#cloud-config"));
    EXPECT_THAT(rendered, HasSubstr("/opt/note.txt"));
    EXPECT_THAT(rendered, HasSubstr("elp-llm-gateway.crt"));
    EXPECT_THAT(rendered, HasSubstr("update-ca-certificates"));
    EXPECT_EQ(api::first_marketplace_ingress_port(*latest), 5678);

    ::unsetenv("ELP_MARKETPLACE_DIR");
}

namespace
{
struct PemX509
{
    explicit PemX509(const std::string& pem)
        : bio{BIO_new_mem_buf(pem.data(), static_cast<int>(pem.size()))},
          cert{PEM_read_bio_X509(bio, nullptr, nullptr, nullptr), X509_free}
    {
        EXPECT_NE(bio, nullptr);
        EXPECT_NE(cert.get(), nullptr);
    }

    ~PemX509()
    {
        BIO_free(bio);
    }

    PemX509(const PemX509&) = delete;
    PemX509& operator=(const PemX509&) = delete;

    BIO* bio;
    std::unique_ptr<X509, decltype(&X509_free)> cert;
};

bool has_eku(X509& cert, int nid)
{
    int crit = 0;
    auto* eku = reinterpret_cast<STACK_OF(ASN1_OBJECT)*>(
        X509_get_ext_d2i(&cert, NID_ext_key_usage, &crit, nullptr));
    if (!eku)
        return false;
    bool found = false;
    for (int i = 0; i < sk_ASN1_OBJECT_num(eku); ++i)
    {
        if (OBJ_obj2nid(sk_ASN1_OBJECT_value(eku, i)) == nid)
            found = true;
    }
    sk_ASN1_OBJECT_pop_free(eku, ASN1_OBJECT_free);
    return found;
}

std::vector<std::string> san_entries(X509& cert)
{
    std::vector<std::string> out;
    auto* names = reinterpret_cast<GENERAL_NAMES*>(
        X509_get_ext_d2i(&cert, NID_subject_alt_name, nullptr, nullptr));
    if (!names)
        return out;
    for (int i = 0; i < sk_GENERAL_NAME_num(names); ++i)
    {
        auto* name = sk_GENERAL_NAME_value(names, i);
        if (name->type == GEN_DNS)
        {
            const auto* str = name->d.dNSName;
            out.emplace_back(fmt::format("DNS:{}",
                                         std::string(reinterpret_cast<const char*>(ASN1_STRING_get0_data(str)),
                                                     static_cast<std::size_t>(ASN1_STRING_length(str)))));
        }
        else if (name->type == GEN_IPADD)
        {
            const auto* ip = name->d.iPAddress;
            if (ASN1_STRING_length(ip) == 4)
            {
                const auto* d = ASN1_STRING_get0_data(ip);
                out.push_back(fmt::format("IP:{}.{}.{}.{}", d[0], d[1], d[2], d[3]));
            }
        }
    }
    sk_GENERAL_NAME_pop_free(names, GENERAL_NAME_free);
    return out;
}
} // namespace

TEST(ApiHttpsCerts, generatesCaAndServerAuthLeafWithSans)
{
    mpt::MockLogger::Scope logger_scope = mpt::MockLogger::inject();
    mpt::TempDir temp_dir;
    const auto material =
        api::load_or_create_https_certs(temp_dir.path(), {"127.0.0.1", "192.168.67.1"});

    EXPECT_THAT(material.ca_pem, HasSubstr("BEGIN CERTIFICATE"));
    EXPECT_THAT(material.cert_pem, HasSubstr("BEGIN CERTIFICATE"));
    EXPECT_THAT(material.key_pem, HasSubstr("BEGIN"));

    const PemX509 ca{material.ca_pem};
    const PemX509 leaf{material.cert_pem};
    EXPECT_GT(X509_check_ca(ca.cert.get()), 0);
    EXPECT_TRUE(has_eku(*leaf.cert, NID_server_auth));
    EXPECT_FALSE(has_eku(*leaf.cert, NID_client_auth));

    const auto sans = san_entries(*leaf.cert);
    EXPECT_THAT(sans, Contains("DNS:localhost"));
    EXPECT_THAT(sans, Contains("IP:127.0.0.1"));
    EXPECT_THAT(sans, Contains("IP:192.168.67.1"));

    const auto fp = api::fingerprint_from_pem(material.cert_pem);
    EXPECT_THAT(fp, HasSubstr(":"));
    EXPECT_NE(fp, api::fingerprint_from_pem(material.ca_pem));

    const auto reused = api::load_or_create_https_certs(temp_dir.path(), {"10.0.0.1"});
    EXPECT_EQ(reused.cert_pem, material.cert_pem);
    EXPECT_EQ(reused.ca_pem, material.ca_pem);
}

