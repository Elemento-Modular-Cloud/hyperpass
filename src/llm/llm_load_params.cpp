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

#include "llm_load_params.h"

#include <QRegularExpression>
#include <QString>

#include <algorithm>

namespace mp = multipass;

namespace
{
QString lowered(const std::string& value)
{
    return QString::fromStdString(value).trimmed().toLower();
}

QString nonempty_or(const std::string& value, const QString& fallback)
{
    const auto trimmed = QString::fromStdString(value).trimmed();
    return trimmed.isEmpty() ? fallback : trimmed;
}
} // namespace

bool mp::looks_like_moe_model(const std::string& model_id)
{
    const auto id = QString::fromStdString(model_id);
    if (id.isEmpty())
        return false;
    static const QRegularExpression moe_re{
        QStringLiteral(R"(mixtral|(?<![a-z])moe(?![a-z])|[-_.]a3b([-_.]|$)|[-_.]a2b([-_.]|$)|gpt-oss|deepseek-v3)"),
        QRegularExpression::CaseInsensitiveOption};
    return moe_re.match(id).hasMatch();
}

double mp::kv_cache_byte_scale(const std::string& cache_type_k, const std::string& cache_type_v)
{
    const auto scale_of = [](const QString& type) {
        if (type == "q4_0" || type == "q4_1" || type == "iq4_nl")
            return 0.25;
        if (type == "q8_0" || type == "q5_0" || type == "q5_1")
            return 0.5;
        return 1.0;
    };
    return (scale_of(lowered(cache_type_k)) + scale_of(lowered(cache_type_v))) / 2.0;
}

mp::ResolvedLlmLoad mp::resolve_llm_load(const LoadModelRequest& request, bool gpu_available)
{
    const auto& p = request.params();
    ResolvedLlmLoad out;

    if (p.has_ctx_size() && p.ctx_size() > 0)
        out.ctx_size = p.ctx_size();
    else if (request.ctx_size() > 0)
        out.ctx_size = request.ctx_size();
    else
        out.ctx_size = 4096;

    if (p.has_max_tokens())
        out.max_tokens = std::max(0, p.max_tokens());
    else
        out.max_tokens = request.max_tokens() > 0 ? request.max_tokens() : 0;

    const auto ngl = nonempty_or(p.n_gpu_layers(), gpu_available ? QStringLiteral("auto") : QStringLiteral("0"));
    const auto flash = nonempty_or(p.flash_attn(), QStringLiteral("auto")).toLower();
    const auto cache_k = nonempty_or(p.cache_type_k(), QStringLiteral("q8_0"));
    const auto cache_v = nonempty_or(p.cache_type_v(), cache_k);
    const auto cache_reuse = p.has_cache_reuse() ? std::max(0, p.cache_reuse()) : 256;
    const auto fit = p.has_fit() ? p.fit() : true;
    const auto parallel = p.has_parallel() && p.parallel() > 0 ? p.parallel() : 1;
    const auto moe = nonempty_or(p.moe_offload(), QStringLiteral("auto")).toLower();
    const auto cpu_moe = moe == "cpu" || (moe == "auto" && looks_like_moe_model(request.model_id()));
    const auto load_mode = QString::fromStdString(p.load_mode()).trimmed();

    out.llama.ctx_size = out.ctx_size;
    out.llama.max_tokens = out.max_tokens;
    out.llama.n_gpu_layers = ngl;
    out.llama.flash_attn = flash;
    out.llama.cache_type_k = cache_k;
    out.llama.cache_type_v = cache_v;
    out.llama.cache_reuse = cache_reuse;
    out.llama.fit = fit;
    out.llama.apply_fit = true;
    out.llama.parallel = parallel;
    out.llama.load_mode = load_mode;
    out.llama.cpu_moe = cpu_moe;
    if (p.has_threads() && p.threads() > 0)
        out.llama.threads = p.threads();
    if (p.has_threads_batch() && p.threads_batch() > 0)
        out.llama.threads_batch = p.threads_batch();
    if (p.has_batch_size() && p.batch_size() > 0)
        out.llama.batch_size = p.batch_size();
    if (p.has_ubatch_size() && p.ubatch_size() > 0)
        out.llama.ubatch_size = p.ubatch_size();
    if (p.has_n_cpu_moe() && p.n_cpu_moe() >= 0)
        out.llama.n_cpu_moe = p.n_cpu_moe();

    auto& echoed = out.echoed;
    echoed.set_ctx_size(out.ctx_size);
    echoed.set_max_tokens(out.max_tokens);
    echoed.set_n_gpu_layers(ngl.toStdString());
    echoed.set_flash_attn(flash.toStdString());
    echoed.set_cache_type_k(cache_k.toStdString());
    echoed.set_cache_type_v(cache_v.toStdString());
    echoed.set_cache_reuse(cache_reuse);
    echoed.set_fit(fit);
    echoed.set_parallel(parallel);
    echoed.set_moe_offload(moe.toStdString());
    if (!load_mode.isEmpty())
        echoed.set_load_mode(load_mode.toStdString());
    if (out.llama.threads > 0)
        echoed.set_threads(out.llama.threads);
    if (out.llama.threads_batch > 0)
        echoed.set_threads_batch(out.llama.threads_batch);
    if (out.llama.batch_size > 0)
        echoed.set_batch_size(out.llama.batch_size);
    if (out.llama.ubatch_size > 0)
        echoed.set_ubatch_size(out.llama.ubatch_size);
    if (out.llama.n_cpu_moe >= 0)
        echoed.set_n_cpu_moe(out.llama.n_cpu_moe);

    return out;
}

void mp::apply_resolved_to_options(LlamaServerOptions& options, const ResolvedLlmLoad& resolved)
{
    options.ctx_size = resolved.llama.ctx_size;
    options.max_tokens = resolved.llama.max_tokens;
    options.n_gpu_layers = resolved.llama.n_gpu_layers;
    options.flash_attn = resolved.llama.flash_attn;
    options.cache_type_k = resolved.llama.cache_type_k;
    options.cache_type_v = resolved.llama.cache_type_v;
    options.threads = resolved.llama.threads;
    options.threads_batch = resolved.llama.threads_batch;
    options.batch_size = resolved.llama.batch_size;
    options.ubatch_size = resolved.llama.ubatch_size;
    options.parallel = resolved.llama.parallel;
    options.cache_reuse = resolved.llama.cache_reuse;
    options.fit = resolved.llama.fit;
    options.apply_fit = resolved.llama.apply_fit;
    options.load_mode = resolved.llama.load_mode;
    options.cpu_moe = resolved.llama.cpu_moe;
    options.n_cpu_moe = resolved.llama.n_cpu_moe;
}

QJsonObject mp::llm_load_params_to_json(const LlmLoadParams& params)
{
    QJsonObject obj;
    if (params.has_ctx_size())
        obj["ctx_size"] = params.ctx_size();
    if (params.has_max_tokens())
        obj["max_tokens"] = params.max_tokens();
    if (!params.n_gpu_layers().empty())
        obj["n_gpu_layers"] = QString::fromStdString(params.n_gpu_layers());
    if (!params.flash_attn().empty())
        obj["flash_attn"] = QString::fromStdString(params.flash_attn());
    if (!params.cache_type_k().empty())
        obj["cache_type_k"] = QString::fromStdString(params.cache_type_k());
    if (!params.cache_type_v().empty())
        obj["cache_type_v"] = QString::fromStdString(params.cache_type_v());
    if (params.has_threads())
        obj["threads"] = params.threads();
    if (params.has_threads_batch())
        obj["threads_batch"] = params.threads_batch();
    if (params.has_batch_size())
        obj["batch_size"] = params.batch_size();
    if (params.has_ubatch_size())
        obj["ubatch_size"] = params.ubatch_size();
    if (params.has_parallel())
        obj["parallel"] = params.parallel();
    if (params.has_cache_reuse())
        obj["cache_reuse"] = params.cache_reuse();
    if (params.has_fit())
        obj["fit"] = params.fit();
    if (!params.load_mode().empty())
        obj["load_mode"] = QString::fromStdString(params.load_mode());
    if (!params.moe_offload().empty())
        obj["moe_offload"] = QString::fromStdString(params.moe_offload());
    if (params.has_n_cpu_moe())
        obj["n_cpu_moe"] = params.n_cpu_moe();
    return obj;
}

mp::LlmLoadParams mp::llm_load_params_from_json(const QJsonObject& obj)
{
    LlmLoadParams params;
    if (obj.contains("ctx_size"))
        params.set_ctx_size(obj.value("ctx_size").toInt());
    if (obj.contains("max_tokens"))
        params.set_max_tokens(obj.value("max_tokens").toInt());
    if (obj.contains("n_gpu_layers"))
        params.set_n_gpu_layers(obj.value("n_gpu_layers").toString().toStdString());
    if (obj.contains("flash_attn"))
        params.set_flash_attn(obj.value("flash_attn").toString().toStdString());
    if (obj.contains("cache_type_k"))
        params.set_cache_type_k(obj.value("cache_type_k").toString().toStdString());
    if (obj.contains("cache_type_v"))
        params.set_cache_type_v(obj.value("cache_type_v").toString().toStdString());
    if (obj.contains("threads"))
        params.set_threads(obj.value("threads").toInt());
    if (obj.contains("threads_batch"))
        params.set_threads_batch(obj.value("threads_batch").toInt());
    if (obj.contains("batch_size"))
        params.set_batch_size(obj.value("batch_size").toInt());
    if (obj.contains("ubatch_size"))
        params.set_ubatch_size(obj.value("ubatch_size").toInt());
    if (obj.contains("parallel"))
        params.set_parallel(obj.value("parallel").toInt());
    if (obj.contains("cache_reuse"))
        params.set_cache_reuse(obj.value("cache_reuse").toInt());
    if (obj.contains("fit"))
        params.set_fit(obj.value("fit").toBool());
    if (obj.contains("load_mode"))
        params.set_load_mode(obj.value("load_mode").toString().toStdString());
    if (obj.contains("moe_offload"))
        params.set_moe_offload(obj.value("moe_offload").toString().toStdString());
    if (obj.contains("n_cpu_moe"))
        params.set_n_cpu_moe(obj.value("n_cpu_moe").toInt());
    return params;
}
