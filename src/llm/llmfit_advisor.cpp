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

#include "llmfit_advisor.h"
#include "binary_locator.h"

#include <multipass/constants.h>
#include <multipass/format.h>
#include <multipass/logging/log.h>
#include <multipass/platform.h>
#include <multipass/process/process.h>
#include <multipass/process/simple_process_spec.h>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

#include <algorithm>
#include <mutex>
#include <stdexcept>

namespace mp = multipass;
namespace mpl = multipass::logging;

namespace
{
constexpr auto category = "llmfit";
constexpr auto cache_ttl = std::chrono::seconds{60};

QString ram_flag(const mp::MemorySize& size)
{
    const auto gb = std::max(1LL, (size.in_bytes() + (1LL << 29)) / (1LL << 30));
    return QString::number(gb) + "G";
}

mp::ModelSuggestion suggestion_from_json(const QJsonObject& obj)
{
    mp::ModelSuggestion s;
    const auto name = obj.value("name").toString();
    s.set_id(name.toStdString());
    s.set_name(name.toStdString());
    s.set_provider(obj.value("provider").toString().toStdString());
    s.set_parameter_count(obj.value("parameter_count").toString().toStdString());
    auto fit = obj.value("fit_level").toString().toLower();
    s.set_fit_level(fit.toStdString());
    s.set_score(obj.value("score").toDouble());
    s.set_best_quant(obj.value("best_quant").toString().toStdString());
    s.set_memory_required_gb(obj.value("memory_required_gb").toDouble());
    s.set_estimated_tps(obj.value("estimated_tps").toDouble());
    auto runtime = obj.value("runtime").toString().toLower();
    if (runtime.contains("mlx"))
        runtime = "mlx";
    else if (runtime.contains("llama"))
        runtime = "llamacpp";
    s.set_runtime(runtime.toStdString());
    s.set_use_case(obj.value("use_case").toString().toLower().toStdString());

    const auto sources = obj.value("gguf_sources").toArray();
    if (!sources.isEmpty())
    {
        const auto src = sources.first().toString();
        auto repo = src;
        repo.replace("https://huggingface.co/", "");
        repo.remove(QRegularExpression("/+$"));
        s.set_hf_repo(repo.toStdString());
    }
    if (obj.contains("hf_repo"))
        s.set_hf_repo(obj.value("hf_repo").toString().toStdString());
    if (obj.contains("filename"))
        s.set_filename(obj.value("filename").toString().toStdString());
    return s;
}

QByteArray run_llmfit(const QString& binary, const QStringList& args, int timeout_ms)
{
    auto process = mp::platform::make_process(mp::simple_process_spec(binary, args));
    const auto state = process->execute(timeout_ms);
    const auto out = process->read_all_standard_output();
    const auto err = process->read_all_standard_error();
    if (!state.completed_successfully())
    {
        throw std::runtime_error(fmt::format("llmfit failed: {} {}",
                                             state.failure_message().toStdString(),
                                             err.toStdString()));
    }
    return out;
}

QString gguf_search_query(QString model_id)
{
    if (model_id.contains('/'))
        model_id = model_id.section('/', -1);

    const QStringList suffixes{"-MLX-8bit",
                               "-MLX-6bit",
                               "-MLX-5bit",
                               "-MLX-4bit",
                               "-MLX-3bit",
                               "-MLX-2bit",
                               "-GGUF",
                               "-MLX",
                               "-8bit",
                               "-6bit",
                               "-5bit",
                               "-4bit",
                               "-3bit",
                               "-2bit",
                               "-FP8",
                               "-bf16",
                               "-BF16"};
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

bool is_mlx_quant(const QString& quant)
{
    return quant.startsWith("mlx", Qt::CaseInsensitive);
}

QString pick_gguf_file(const QStringList& files, const QString& quant)
{
    const auto usable = [&files] {
        QStringList out;
        for (const auto& file : files)
        {
            if (!file.contains("-of-"))
                out << file;
        }
        return out;
    }();
    if (usable.isEmpty())
        return {};

    auto exact = [&](const QString& tag) -> QString {
        const auto needle = QString{"-%1.gguf"}.arg(tag);
        for (const auto& file : usable)
        {
            if (file.endsWith(needle, Qt::CaseInsensitive))
                return file;
        }
        return {};
    };

    if (!quant.isEmpty() && !is_mlx_quant(quant))
    {
        if (auto hit = exact(quant); !hit.isEmpty())
            return hit;
    }
    for (const auto& pref : {"Q4_K_M", "Q5_K_M", "Q6_K", "Q4_K_S", "Q8_0", "Q4_0"})
    {
        if (auto hit = exact(pref); !hit.isEmpty())
            return hit;
    }
    return usable.first();
}

std::optional<mp::ResolvedGguf> parse_download_list(const QString& text, const QString& quant)
{
    static const QRegularExpression repo_re{
        R"(Available GGUF files in (\S+):|Fetching available files from (\S+))"};
    const auto repo_match = repo_re.match(text);
    if (!repo_match.hasMatch())
        return std::nullopt;

    auto repo = repo_match.captured(1);
    if (repo.isEmpty())
        repo = repo_match.captured(2);
    while (repo.endsWith('.'))
        repo.chop(1);

    QStringList files;
    static const QRegularExpression file_re{R"(^(\S+\.gguf)\b)", QRegularExpression::MultilineOption};
    for (auto it = file_re.globalMatch(text); it.hasNext();)
        files << it.next().captured(1);

    const auto filename = pick_gguf_file(files, quant);
    if (repo.isEmpty() || filename.isEmpty())
        return std::nullopt;

    mp::ResolvedGguf resolved;
    resolved.repo = repo.toStdString();
    resolved.filename = filename.toStdString();
    return resolved;
}

QJsonDocument parse_json_payload(const QByteArray& raw)
{
    auto trimmed = raw.trimmed();
    const auto first_brace = trimmed.indexOf('{');
    const auto first_bracket = trimmed.indexOf('[');
    int start = -1;
    if (first_brace >= 0 && (first_bracket < 0 || first_brace < first_bracket))
        start = first_brace;
    else
        start = first_bracket;
    if (start > 0)
        trimmed = trimmed.mid(start);
    QJsonParseError err{};
    auto doc = QJsonDocument::fromJson(trimmed, &err);
    if (err.error != QJsonParseError::NoError)
        throw std::runtime_error(fmt::format("llmfit JSON parse error: {}", err.errorString().toStdString()));
    return doc;
}
} // namespace

QString mp::LlmfitAdvisor::binary_path() const
{
    return llm::locate_binary(mp::llmfit_env_var, {"llmfit"});
}

std::string mp::LlmfitAdvisor::missing_binary_hint() const
{
    return "llmfit is not installed. Install it from https://github.com/AlexsJones/llmfit "
           "or set HYPERPASS_LLMFIT to the binary path. Loaded models and the OpenAI API still work.";
}

std::vector<mp::ModelSuggestion> mp::LlmfitAdvisor::recommend(MemorySize available_ram,
                                                              int cpu_cores,
                                                              const std::string& runtime,
                                                              const std::string& use_case,
                                                              const std::string& min_fit,
                                                              int limit,
                                                              bool unified_memory)
{
    const auto binary = binary_path();
    if (binary.isEmpty())
        throw std::runtime_error(missing_binary_hint());

    std::lock_guard lock{mutex};
    const auto now = std::chrono::steady_clock::now();
    if (cache && cache->available_bytes == available_ram.in_bytes() && cache->runtime == runtime &&
        cache->use_case == use_case && now - cache->at < cache_ttl)
        return cache->models;

    // --ram/--cpu-cores/--memory are global flags; clap rejects them after `recommend`.
    QStringList args{"--json",
                     "--no-dashboard",
                     "--ram",
                     ram_flag(available_ram),
                     "--cpu-cores",
                     QString::number(std::max(cpu_cores, 1))};
    if (unified_memory)
        args << "--memory" << ram_flag(available_ram);

    args << "recommend" << "--limit" << QString::number(limit > 0 ? limit : 10);

    const auto rt = QString::fromStdString(runtime).toLower();
    if (rt.contains("mlx"))
        args << "--runtime" << "mlx";
    else if (!rt.isEmpty())
        args << "--force-runtime" << "llamacpp";

    if (!use_case.empty())
        args << "--use-case" << QString::fromStdString(use_case);
    if (!min_fit.empty())
        args << "--min-fit" << QString::fromStdString(min_fit);

    mpl::info(category, "running {} {}", binary, args.join(' '));
    const auto doc = parse_json_payload(run_llmfit(binary, args, 60000));
    QJsonArray models_json;
    if (doc.isObject())
        models_json = doc.object().value("models").toArray();
    else if (doc.isArray())
        models_json = doc.array();

    std::vector<ModelSuggestion> models;
    for (const auto& item : models_json)
    {
        if (item.isObject())
            models.push_back(suggestion_from_json(item.toObject()));
    }

    cache = CacheEntry{available_ram.in_bytes(), runtime, use_case, now, models};
    return models;
}

std::optional<mp::ResolvedGguf> mp::LlmfitAdvisor::resolve(const std::string& model_id,
                                                           const std::string& quant)
{
    const auto binary = binary_path();
    if (binary.isEmpty())
        return std::nullopt;

    std::lock_guard lock{mutex};
    const auto q = QString::fromStdString(quant);

    auto try_list = [&](const QString& query) -> std::optional<ResolvedGguf> {
        if (query.trimmed().isEmpty())
            return std::nullopt;
        try
        {
            // download --list prints a table (not JSON) and often names a different GGUF repo
            // than llmfit recommend (which returns MLX/base checkpoint ids).
            auto process = mp::platform::make_process(
                mp::simple_process_spec(binary, QStringList{"--no-dashboard", "download", query, "--list"}));
            process->execute(60000);
            const auto text = QString::fromUtf8(process->read_all_standard_output() +
                                                process->read_all_standard_error());
            if (text.contains("No GGUF files found"))
                return std::nullopt;
            auto resolved = parse_download_list(text, q);
            if (resolved)
            {
                mpl::info(category,
                          "resolved {} -> {}/{}",
                          query,
                          resolved->repo,
                          resolved->filename);
            }
            return resolved;
        }
        catch (const std::exception& e)
        {
            mpl::warn(category, "llmfit download --list '{}' failed: {}", query, e.what());
            return std::nullopt;
        }
    };

    QStringList queries{QString::fromStdString(model_id)};
    const auto search = gguf_search_query(QString::fromStdString(model_id));
    if (!search.isEmpty() && !queries.contains(search))
        queries << search;

    for (const auto& query : queries)
    {
        if (auto resolved = try_list(query))
            return resolved;
    }
    return std::nullopt;
}
