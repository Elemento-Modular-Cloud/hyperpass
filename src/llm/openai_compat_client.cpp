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

#include "openai_compat_client.h"

#include <multipass/format.h>

#include <QEventLoop>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QObject>
#include <QTimer>
#include <QUrl>

#include <stdexcept>

namespace mp = multipass;

namespace
{
std::string join_url(const std::string& base_url, const std::string& path)
{
    std::string base = base_url;
    while (!base.empty() && base.back() == '/')
        base.pop_back();
    if (path.empty())
        return base;
    if (path.front() == '/')
        return base + path;
    return base + "/" + path;
}
} // namespace

std::vector<mp::OpenAiCompatModel> mp::openai_compat_list_models(const std::string& base_url,
                                                                 const std::string& api_key)
{
    if (base_url.empty())
        throw std::runtime_error("provider base URL is empty");
    if (api_key.empty())
        throw std::runtime_error("provider API key is empty");

    const QUrl url{QString::fromStdString(join_url(base_url, "/models"))};
    if (!url.isValid() || url.scheme().isEmpty())
        throw std::runtime_error(fmt::format("invalid provider URL '{}'", base_url));

    QNetworkRequest request{url};
    request.setRawHeader("Authorization", QByteArray("Bearer ") + QByteArray::fromStdString(api_key));
    request.setRawHeader("Accept", "application/json");
    // Anthropic's OpenAI-compat endpoint also expects this header.
    if (base_url.find("api.anthropic.com") != std::string::npos)
        request.setRawHeader("anthropic-version", "2023-06-01");

    QNetworkAccessManager manager;
    QEventLoop loop;
    QTimer timer;
    timer.setSingleShot(true);
    QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);

    auto* reply = manager.get(request);
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    timer.start(60000);
    loop.exec();

    if (!timer.isActive())
    {
        reply->abort();
        reply->deleteLater();
        throw std::runtime_error("timed out listing models from provider");
    }
    timer.stop();

    const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const auto body = reply->readAll();
    const auto error = reply->error();
    reply->deleteLater();

    if (error != QNetworkReply::NoError)
        throw std::runtime_error(fmt::format("provider /models request failed: {}",
                                             body.isEmpty() ? "network error" : body.constData()));
    if (status < 200 || status >= 300)
        throw std::runtime_error(
            fmt::format("provider /models returned HTTP {}: {}", status, body.constData()));

    const auto doc = QJsonDocument::fromJson(body);
    if (!doc.isObject())
        throw std::runtime_error("provider /models response is not a JSON object");

    const auto data = doc.object().value("data");
    if (!data.isArray())
        throw std::runtime_error("provider /models response missing data array");

    std::vector<OpenAiCompatModel> models;
    for (const auto& item : data.toArray())
    {
        if (!item.isObject())
            continue;
        const auto obj = item.toObject();
        OpenAiCompatModel model;
        model.id = obj.value("id").toString().toStdString();
        model.owned_by = obj.value("owned_by").toString().toStdString();
        if (!model.id.empty())
            models.push_back(std::move(model));
    }
    return models;
}
