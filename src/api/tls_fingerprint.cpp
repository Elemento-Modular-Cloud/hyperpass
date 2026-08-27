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

#include "tls_fingerprint.h"

#include <multipass/format.h>
#include <multipass/utils.h>

#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

#include <array>
#include <memory>
#include <stdexcept>
#include <vector>

namespace mp = multipass;

namespace
{
struct BioDeleter
{
    void operator()(BIO* bio) const
    {
        BIO_free(bio);
    }
};

struct BioAllDeleter
{
    void operator()(BIO* bio) const
    {
        BIO_free_all(bio);
    }
};

struct SslCtxDeleter
{
    void operator()(SSL_CTX* ctx) const
    {
        SSL_CTX_free(ctx);
    }
};

struct X509Deleter
{
    void operator()(X509* cert) const
    {
        X509_free(cert);
    }
};

std::string format_sha256_colon(const unsigned char* digest, std::size_t len)
{
    static constexpr char hex[] = "0123456789ABCDEF";
    std::string out;
    out.reserve(len * 3);
    for (std::size_t i = 0; i < len; ++i)
    {
        if (i)
            out.push_back(':');
        out.push_back(hex[(digest[i] >> 4) & 0xF]);
        out.push_back(hex[digest[i] & 0xF]);
    }
    return out;
}

std::string openssl_errors()
{
    std::string out;
    while (auto err = ERR_get_error())
    {
        if (!out.empty())
            out.push_back(';');
        char buf[256];
        ERR_error_string_n(err, buf, sizeof(buf));
        out += buf;
    }
    return out.empty() ? "unknown OpenSSL error" : out;
}

std::string der_from_x509(X509* cert)
{
    const int der_len = i2d_X509(cert, nullptr);
    if (der_len <= 0)
        throw std::runtime_error("failed to encode peer certificate as DER");

    std::vector<unsigned char> der(static_cast<std::size_t>(der_len));
    auto* out = der.data();
    if (i2d_X509(cert, &out) != der_len)
        throw std::runtime_error("failed to encode peer certificate as DER");

    return {reinterpret_cast<const char*>(der.data()), der.size()};
}

std::string fetch_peer_der(const std::string& host, int port, int timeout_sec, bool verify)
{
    std::unique_ptr<SSL_CTX, SslCtxDeleter> ctx{SSL_CTX_new(TLS_client_method())};
    if (!ctx)
        throw std::runtime_error(fmt::format("SSL_CTX_new failed: {}", openssl_errors()));

    if (verify)
    {
        SSL_CTX_set_default_verify_paths(ctx.get());
        SSL_CTX_set_verify(ctx.get(), SSL_VERIFY_PEER, nullptr);
    }
    else
    {
        SSL_CTX_set_verify(ctx.get(), SSL_VERIFY_NONE, nullptr);
    }

    std::unique_ptr<BIO, BioAllDeleter> bio{BIO_new_ssl_connect(ctx.get())};
    if (!bio)
        throw std::runtime_error(fmt::format("BIO_new_ssl_connect failed: {}", openssl_errors()));

    SSL* ssl = nullptr;
    BIO_get_ssl(bio.get(), &ssl);
    if (!ssl)
        throw std::runtime_error("BIO_get_ssl failed");

    SSL_set_mode(ssl, SSL_MODE_AUTO_RETRY);
    SSL_set_tlsext_host_name(ssl, host.c_str());
    if (verify)
        SSL_set1_host(ssl, host.c_str());

    const auto target = fmt::format("{}:{}", host, port);
    BIO_set_conn_hostname(bio.get(), target.c_str());
    (void)timeout_sec;

    if (BIO_do_connect(bio.get()) <= 0)
    {
        throw std::runtime_error(
            fmt::format("TLS connect to {} failed: {}", target, openssl_errors()));
    }

    if (BIO_do_handshake(bio.get()) <= 0)
    {
        throw std::runtime_error(
            fmt::format("TLS handshake with {} failed: {}", target, openssl_errors()));
    }

    if (verify)
    {
        const auto vr = SSL_get_verify_result(ssl);
        if (vr != X509_V_OK)
        {
            throw std::runtime_error(
                fmt::format("TLS certificate verification failed for {}: {}",
                            target,
                            X509_verify_cert_error_string(vr)));
        }
    }

#if OPENSSL_VERSION_NUMBER >= 0x30000000L
    std::unique_ptr<X509, X509Deleter> cert{SSL_get1_peer_certificate(ssl)};
#else
    std::unique_ptr<X509, X509Deleter> cert{SSL_get_peer_certificate(ssl)};
#endif
    if (!cert)
        throw std::runtime_error(fmt::format("no peer certificate from {}", target));

    return der_from_x509(cert.get());
}
} // namespace

std::string mp::api::fingerprint_from_der(std::string_view der)
{
    std::array<unsigned char, EVP_MAX_MD_SIZE> digest{};
    unsigned int digest_len = 0;
    if (EVP_Digest(der.data(),
                   der.size(),
                   digest.data(),
                   &digest_len,
                   EVP_sha256(),
                   nullptr) != 1)
    {
        throw std::runtime_error("failed to compute SHA-256 certificate fingerprint");
    }
    return format_sha256_colon(digest.data(), digest_len);
}

std::string mp::api::fingerprint_from_pem(std::string_view pem)
{
    std::unique_ptr<BIO, BioDeleter> bio{
        BIO_new_mem_buf(pem.data(), static_cast<int>(pem.size()))};
    if (!bio)
        throw std::runtime_error("failed to allocate BIO for certificate PEM");

    // BIO_new_mem_buf ownership: BIO_free (not free_all) — use a one-shot free.
    std::unique_ptr<X509, X509Deleter> cert{PEM_read_bio_X509(bio.get(), nullptr, nullptr, nullptr)};
    if (!cert)
        throw std::runtime_error("failed to parse certificate PEM");

    return fingerprint_from_der(der_from_x509(cert.get()));
}

std::string mp::api::fingerprint_from_pem_file(const std::string& path)
{
    return fingerprint_from_pem(MP_UTILS.contents_of(QString::fromStdString(path)));
}

mp::api::RemoteCertInfo mp::api::fetch_remote_tls_cert(const std::string& host,
                                                       int port,
                                                       int timeout_sec)
{
    if (host.empty())
        throw std::runtime_error("host is required");
    if (port <= 0 || port > 65535)
        throw std::runtime_error(fmt::format("invalid port {}", port));

    // Electros: first connection CERT_NONE to obtain DER, second with verify for validated.
    const auto der = fetch_peer_der(host, port, timeout_sec, /*verify=*/false);
    RemoteCertInfo info;
    info.fingerprint = fingerprint_from_der(der);

    try
    {
        const auto verified_der = fetch_peer_der(host, port, timeout_sec, /*verify=*/true);
        if (verified_der != der)
        {
            throw std::runtime_error(
                fmt::format("certificate changed during validation for {}:{}", host, port));
        }
        info.validated = true;
    }
    catch (const std::exception&)
    {
        info.validated = false;
    }

    return info;
}

mp::api::RemoteCertInfo mp::api::fetch_remote_tls_cert_atomos(const std::string& host,
                                                              int timeout_sec)
{
    try
    {
        return fetch_remote_tls_cert(host, atomos_matcher_tls_port, timeout_sec);
    }
    catch (const std::exception&)
    {
        return fetch_remote_tls_cert(host, atomos_storage_tls_port, timeout_sec);
    }
}
