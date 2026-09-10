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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */

#include "https_certs.h"

#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/platform.h>
#include <multipass/utils.h>

#include <openssl/core_names.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rand.h>
#include <openssl/x509v3.h>

#include <QDir>
#include <QFile>

#include <array>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto log_category = "https-certs";
constexpr auto ca_pem_name = "ca.pem";
constexpr auto ca_key_name = "ca_key.pem";
constexpr auto server_pem_name = "server.pem";
constexpr auto server_key_name = "server_key.pem";

template <typename T>
void openssl_check(T* result, const std::string& error)
{
    if (result == nullptr)
        throw std::runtime_error(error);
}

void openssl_check(int result, const std::string& error)
{
    if (result <= 0)
        throw std::runtime_error(fmt::format("{}, with the error code {}", error, result));
}

struct FileCloser
{
    void operator()(FILE* fp) const
    {
        if (fp)
            fclose(fp);
    }
};

std::unique_ptr<FILE, FileCloser> open_write(const QString& path)
{
    const std::filesystem::path std_path{path.toStdString()};
    std::filesystem::create_directories(std_path.parent_path());
    auto* fp = fopen(std_path.string().c_str(), "wb");
    openssl_check(fp, fmt::format("failed to open '{}'", path.toStdString()));
    return {fp, FileCloser{}};
}

using EvpPkeyPtr = std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)>;
using X509Ptr = std::unique_ptr<X509, decltype(&X509_free)>;

EvpPkeyPtr generate_ec_key()
{
    std::unique_ptr<EVP_PKEY_CTX, decltype(&EVP_PKEY_CTX_free)> ctx(
        EVP_PKEY_CTX_new_from_name(nullptr, "EC", nullptr),
        EVP_PKEY_CTX_free);
    openssl_check(ctx.get(), "Failed to create EVP_PKEY_CTX");
    openssl_check(EVP_PKEY_keygen_init(ctx.get()), "Failed to initialize key generation");

    const std::array<OSSL_PARAM, 2> params = {
        OSSL_PARAM_construct_utf8_string(OSSL_PKEY_PARAM_GROUP_NAME, const_cast<char*>("P-256"), 0),
        OSSL_PARAM_construct_end()};
    openssl_check(EVP_PKEY_CTX_set_params(ctx.get(), params.data()), "EVP_PKEY_CTX_set_params() failed");

    EVP_PKEY* raw = nullptr;
    openssl_check(EVP_PKEY_generate(ctx.get(), &raw), "Failed to generate EC key");
    return {raw, EVP_PKEY_free};
}

void set_random_serial(X509* cert)
{
    std::array<uint8_t, 20> serial_bytes{};
    openssl_check(RAND_bytes(serial_bytes.data(), serial_bytes.size()), "Failed to set random bytes");
    serial_bytes[0] &= 0x7F;

    std::unique_ptr<BIGNUM, decltype(&BN_free)> bn(
        BN_bin2bn(serial_bytes.data(), static_cast<int>(serial_bytes.size()), nullptr),
        BN_free);
    openssl_check(bn.get(), "Failed to convert serial bytes to BIGNUM");

    std::unique_ptr<ASN1_INTEGER, decltype(&ASN1_INTEGER_free)> serial{BN_to_ASN1_INTEGER(bn.get(), nullptr),
                                                                       ASN1_INTEGER_free};
    openssl_check(serial.get(), "Failed to convert serial to ASN1_INTEGER");
    openssl_check(X509_set_serialNumber(cert, serial.get()), "Failed to set serial number");
}

void add_name_entries(X509_NAME* name, const char* cn)
{
    constexpr int append_entry{-1};
    constexpr int add_rdn{0};
    openssl_check(X509_NAME_add_entry_by_txt(name, "C", MBSTRING_ASC, reinterpret_cast<const unsigned char*>("US"), -1,
                                             append_entry, add_rdn),
                  "Failed to set C");
    openssl_check(X509_NAME_add_entry_by_txt(name,
                                             "O",
                                             MBSTRING_ASC,
                                             reinterpret_cast<const unsigned char*>("Elemento"),
                                             -1,
                                             append_entry,
                                             add_rdn),
                  "Failed to set O");
    openssl_check(X509_NAME_add_entry_by_txt(name,
                                             "CN",
                                             MBSTRING_ASC,
                                             reinterpret_cast<const unsigned char*>(cn),
                                             -1,
                                             append_entry,
                                             add_rdn),
                  "Failed to set CN");
}

void add_extension(X509* cert, X509* issuer, int nid, const char* value)
{
    X509V3_CTX ctx{};
    X509V3_set_ctx(&ctx, issuer, cert, nullptr, nullptr, 0);
    std::unique_ptr<X509_EXTENSION, decltype(&X509_EXTENSION_free)> ext(
        X509V3_EXT_conf_nid(nullptr, &ctx, nid, value),
        X509_EXTENSION_free);
    openssl_check(ext.get(), fmt::format("Failed to create X509 extension {}", nid));
    openssl_check(X509_add_ext(cert, ext.get(), -1), "Failed to add X509 extension");
}

bool is_ipv4(const std::string& host)
{
    int a = -1, b = -1, c = -1, d = -1;
    char extra = '\0';
    if (std::sscanf(host.c_str(), "%d.%d.%d.%d%c", &a, &b, &c, &d, &extra) != 4)
        return false;
    return a >= 0 && a <= 255 && b >= 0 && b <= 255 && c >= 0 && c <= 255 && d >= 0 && d <= 255;
}

std::string san_string(const std::vector<std::string>& listen_hosts)
{
    std::set<std::string> dns{"localhost"};
    std::set<std::string> ips{"127.0.0.1", mp::default_api_vm_gateway};

    for (const auto& host : listen_hosts)
    {
        if (host.empty())
            continue;
        if (is_ipv4(host) || host.find(':') != std::string::npos)
            ips.insert(host);
        else
            dns.insert(host);
    }

    std::string san;
    auto append = [&](const std::string& entry) {
        if (!san.empty())
            san += ',';
        san += entry;
    };
    for (const auto& name : dns)
        append("DNS:" + name);
    for (const auto& ip : ips)
        append("IP:" + ip);
    return san;
}

std::string x509_to_pem(X509* cert)
{
    std::unique_ptr<BIO, decltype(&BIO_free)> bio{BIO_new(BIO_s_mem()), BIO_free};
    openssl_check(bio.get(), "Failed to allocate BIO for certificate PEM");
    openssl_check(PEM_write_bio_X509(bio.get(), cert), "Failed to write certificate PEM");
    char* data = nullptr;
    const auto len = BIO_get_mem_data(bio.get(), &data);
    return {data, static_cast<std::string::size_type>(len)};
}

std::string pkey_to_pem(EVP_PKEY* key)
{
    std::unique_ptr<BIO, decltype(&BIO_free)> bio{BIO_new(BIO_s_mem()), BIO_free};
    openssl_check(bio.get(), "Failed to allocate BIO for key PEM");
    openssl_check(PEM_write_bio_PrivateKey(bio.get(), key, nullptr, nullptr, 0, nullptr, nullptr),
                  "Failed to write private key PEM");
    char* data = nullptr;
    const auto len = BIO_get_mem_data(bio.get(), &data);
    return {data, static_cast<std::string::size_type>(len)};
}

X509Ptr load_cert(const QString& path)
{
    const auto file = fopen(path.toStdString().c_str(), "r");
    if (!file)
        return {nullptr, X509_free};
    std::unique_ptr<FILE, FileCloser> fp{file, FileCloser{}};
    return {PEM_read_X509(fp.get(), nullptr, nullptr, nullptr), X509_free};
}

bool cert_has_eku(X509& cert, int eku_nid)
{
    int crit = 0;
    auto* eku = reinterpret_cast<STACK_OF(ASN1_OBJECT)*>(
        X509_get_ext_d2i(&cert, NID_ext_key_usage, &crit, nullptr));
    if (!eku || crit)
        return false;

    bool found = false;
    for (int i = 0; i < sk_ASN1_OBJECT_num(eku); ++i)
    {
        if (OBJ_obj2nid(sk_ASN1_OBJECT_value(eku, i)) == eku_nid)
        {
            found = true;
            break;
        }
    }
    sk_ASN1_OBJECT_pop_free(eku, ASN1_OBJECT_free);
    return found;
}

void write_pem_file(const QString& path, const std::string& pem, bool private_key)
{
    {
        auto file = open_write(path);
        if (fwrite(pem.data(), 1, pem.size(), file.get()) != pem.size())
            throw std::runtime_error(fmt::format("Failed writing '{}'", path.toStdString()));
    }

    const std::filesystem::path std_path = path.toStdU16String();
    if (private_key)
    {
        MP_PLATFORM.set_permissions(std_path, std::filesystem::perms::owner_read);
    }
    else
    {
        MP_PLATFORM.set_permissions(std_path,
                                    std::filesystem::perms::owner_all | std::filesystem::perms::group_read |
                                        std::filesystem::perms::others_read);
    }
}

mp::api::HttpsCertMaterial generate_pair(const QDir& dir, const std::vector<std::string>& listen_hosts)
{
    auto ca_key = generate_ec_key();
    auto server_key = generate_ec_key();

    X509Ptr ca{X509_new(), X509_free};
    openssl_check(ca.get(), "Failed to allocate CA certificate");
    X509_set_version(ca.get(), 2);
    set_random_serial(ca.get());

    constexpr std::chrono::seconds one_day{24 * 60 * 60};
    constexpr std::chrono::seconds ten_years = one_day * 365 * 10;
    constexpr std::chrono::seconds apple_max = one_day * 825;
    X509_gmtime_adj(X509_get_notBefore(ca.get()), 0);
    X509_gmtime_adj(X509_get_notAfter(ca.get()), ten_years.count());
    add_name_entries(X509_get_subject_name(ca.get()), "Electros LaunchPad API CA");
    X509_set_issuer_name(ca.get(), X509_get_subject_name(ca.get()));
    openssl_check(X509_set_pubkey(ca.get(), ca_key.get()), "Failed to set CA public key");
    add_extension(ca.get(), ca.get(), NID_basic_constraints, "critical,CA:TRUE");
    add_extension(ca.get(), ca.get(), NID_key_usage, "critical,keyCertSign,cRLSign");
    add_extension(ca.get(), ca.get(), NID_subject_key_identifier, "hash");
    openssl_check(X509_sign(ca.get(), ca_key.get(), EVP_sha256()), "Failed to sign CA certificate");

    X509Ptr server{X509_new(), X509_free};
    openssl_check(server.get(), "Failed to allocate server certificate");
    X509_set_version(server.get(), 2);
    set_random_serial(server.get());
    X509_gmtime_adj(X509_get_notBefore(server.get()), 0);
    X509_gmtime_adj(X509_get_notAfter(server.get()), apple_max.count());
    add_name_entries(X509_get_subject_name(server.get()), "localhost");
    X509_set_issuer_name(server.get(), X509_get_subject_name(ca.get()));
    openssl_check(X509_set_pubkey(server.get(), server_key.get()), "Failed to set server public key");
    add_extension(server.get(), ca.get(), NID_basic_constraints, "critical,CA:FALSE");
    add_extension(server.get(), ca.get(), NID_ext_key_usage, "serverAuth");
    add_extension(server.get(), ca.get(), NID_subject_key_identifier, "hash");
    add_extension(server.get(), ca.get(), NID_authority_key_identifier, "keyid:always,issuer");
    const auto san = san_string(listen_hosts);
    add_extension(server.get(), ca.get(), NID_subject_alt_name, san.c_str());
    openssl_check(X509_sign(server.get(), ca_key.get(), EVP_sha256()), "Failed to sign server certificate");

    mp::api::HttpsCertMaterial material;
    material.ca_pem = x509_to_pem(ca.get());
    material.cert_pem = x509_to_pem(server.get());
    material.key_pem = pkey_to_pem(server_key.get());
    const auto ca_key_pem = pkey_to_pem(ca_key.get());

    write_pem_file(dir.filePath(ca_pem_name), material.ca_pem, false);
    write_pem_file(dir.filePath(ca_key_name), ca_key_pem, true);
    write_pem_file(dir.filePath(server_pem_name), material.cert_pem, false);
    write_pem_file(dir.filePath(server_key_name), material.key_pem, true);

    mpl::info(log_category, "Generated HTTPS CA and server certificate (SAN {})", san);
    return material;
}
} // namespace

mp::api::HttpsCertMaterial mp::api::load_or_create_https_certs(const QString& cert_dir,
                                                               const std::vector<std::string>& listen_hosts)
{
    QDir dir{cert_dir};
    if (!dir.exists())
        QDir().mkpath(dir.path());

    const auto ca_path = dir.filePath(ca_pem_name);
    const auto ca_key_path = dir.filePath(ca_key_name);
    const auto server_path = dir.filePath(server_pem_name);
    const auto server_key_path = dir.filePath(server_key_name);

    if (QFile::exists(ca_path) && QFile::exists(ca_key_path) && QFile::exists(server_path) &&
        QFile::exists(server_key_path))
    {
        auto leaf = load_cert(server_path);
        if (leaf && cert_has_eku(*leaf, NID_server_auth))
        {
            mpl::info(log_category, "Re-using HTTPS CA and server certificate under {}", dir.path().toStdString());
            HttpsCertMaterial material;
            material.ca_pem = MP_UTILS.contents_of(ca_path);
            material.cert_pem = MP_UTILS.contents_of(server_path);
            material.key_pem = MP_UTILS.contents_of(server_key_path);
            return material;
        }
        mpl::warn(log_category,
                  "Existing HTTPS leaf under {} is not a serverAuth certificate; regenerating",
                  dir.path().toStdString());
    }

    return generate_pair(dir, listen_hosts);
}
