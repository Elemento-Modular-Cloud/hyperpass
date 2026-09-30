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

#pragma once

#include <QRegularExpression>
#include <QString>
#include <QStringList>

#include <algorithm>
#include <string>
#include <vector>

namespace multipass::llm
{

/// True when [repo] is already an MLX-converted Hugging Face id (not a base
/// PyTorch/safetensors checkpoint). mlx_lm.server must be pointed at one of
/// these; loading deepseek-ai/... downloads the original weights and often
/// fails or stalls mid-fetch while we already declared the session ready.
inline bool looks_like_mlx_repo(const QString& repo)
{
    const auto trimmed = repo.trimmed();
    if (trimmed.isEmpty())
        return false;
    if (trimmed.startsWith(QStringLiteral("mlx-community/"), Qt::CaseInsensitive))
        return true;
    if (trimmed.contains(QStringLiteral("-MLX-"), Qt::CaseInsensitive))
        return true;
    if (trimmed.endsWith(QStringLiteral("-MLX"), Qt::CaseInsensitive))
        return true;
    return false;
}

inline bool looks_like_mlx_repo(const std::string& repo)
{
    return looks_like_mlx_repo(QString::fromStdString(repo));
}

/// Strip org prefix and common MLX/GGUF quant suffixes to get a bare model name.
inline QString mlx_base_name(QString model_id)
{
    if (model_id.contains(QLatin1Char('/')))
        model_id = model_id.section(QLatin1Char('/'), -1);

    const QStringList suffixes{QStringLiteral("-MLX-8bit"),
                               QStringLiteral("-MLX-6bit"),
                               QStringLiteral("-MLX-5bit"),
                               QStringLiteral("-MLX-4bit"),
                               QStringLiteral("-MLX-3bit"),
                               QStringLiteral("-MLX-2bit"),
                               QStringLiteral("-8bit"),
                               QStringLiteral("-6bit"),
                               QStringLiteral("-5bit"),
                               QStringLiteral("-4bit"),
                               QStringLiteral("-3bit"),
                               QStringLiteral("-2bit"),
                               QStringLiteral("-bf16"),
                               QStringLiteral("-BF16"),
                               QStringLiteral("-MLX"),
                               QStringLiteral("-GGUF")};
    bool stripped = true;
    while (stripped)
    {
        stripped = false;
        for (const auto& suffix : suffixes)
        {
            if (model_id.endsWith(suffix, Qt::CaseInsensitive))
            {
                model_id.chop(suffix.size());
                stripped = true;
                break;
            }
        }
    }
    return model_id;
}

/// Map vault/catalogue quant tags (mlx-8bit, 4bit, …) to mlx-community suffixes.
inline QString mlx_bit_tag(const QString& quant)
{
    const auto trimmed = quant.trimmed();
    if (trimmed.compare(QStringLiteral("bf16"), Qt::CaseInsensitive) == 0 ||
        trimmed.compare(QStringLiteral("mlx-bf16"), Qt::CaseInsensitive) == 0)
        return QStringLiteral("bf16");

    static const QRegularExpression re{QStringLiteral(R"((\d+)\s*bit)"),
                                       QRegularExpression::CaseInsensitiveOption};
    const auto match = re.match(trimmed);
    if (match.hasMatch())
        return match.captured(1) + QStringLiteral("bit");

    // mlx-community most often publishes 4bit builds; prefer that over guessing 8bit.
    return QStringLiteral("4bit");
}

inline bool looks_like_chat_tuned_name(const QString& base)
{
    const auto lower = base.toLower();
    return lower.contains(QStringLiteral("-it")) || lower.contains(QStringLiteral("instruct")) ||
           lower.contains(QStringLiteral("-chat")) || lower.contains(QStringLiteral("distill"));
}

/// Ordered mlx-community repo ids to try. Instruct/chat builds come first so
/// base checkpoints (e.g. Gemma-2-2B) are not loaded for chat — those fall back
/// to mlx_lm's USER:/ASSISTANT: prompt and loop.
inline std::vector<std::string> mlx_repo_candidates(const std::string& model_id,
                                                    const std::string& quant,
                                                    const std::string& hf_repo = {})
{
    std::vector<std::string> out;
    auto add = [&](const QString& repo) {
        if (repo.isEmpty())
            return;
        const auto s = repo.toStdString();
        if (std::find(out.begin(), out.end(), s) == out.end())
            out.push_back(s);
    };

    if (!hf_repo.empty() && looks_like_mlx_repo(hf_repo))
        add(QString::fromStdString(hf_repo));
    if (looks_like_mlx_repo(model_id))
        add(QString::fromStdString(model_id));

    const auto base = mlx_base_name(QString::fromStdString(model_id));
    if (base.isEmpty())
        return out;

    const auto bits = mlx_bit_tag(QString::fromStdString(quant));
    const auto lower = base.toLower();
    if (!looks_like_chat_tuned_name(base))
    {
        add(QStringLiteral("mlx-community/%1-it-%2").arg(base, bits));
        add(QStringLiteral("mlx-community/%1-it-%2").arg(lower, bits));
        add(QStringLiteral("mlx-community/%1-Instruct-%2").arg(base, bits));
    }
    add(QStringLiteral("mlx-community/%1-%2").arg(base, bits));
    add(QStringLiteral("mlx-community/%1-%2").arg(lower, bits));
    return out;
}

/// Resolve the Hugging Face repo mlx_lm.server should load.
/// Prefer an explicit MLX hf_repo / model_id; otherwise map base id + quant to
/// an instruct-first mlx-community candidate.
inline std::string resolve_mlx_repo(const std::string& model_id,
                                    const std::string& quant,
                                    const std::string& hf_repo = {})
{
    const auto candidates = mlx_repo_candidates(model_id, quant, hf_repo);
    return candidates.empty() ? std::string{} : candidates.front();
}

} // namespace multipass::llm
