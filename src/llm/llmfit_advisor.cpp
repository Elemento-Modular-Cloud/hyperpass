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
#include "managed_tools.h"

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
#include <QSet>

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
    s.set_disk_size_gb(obj.value("disk_size_gb").toDouble());
    s.set_run_mode(obj.value("run_mode").toString().toStdString());
    s.set_utilization_pct(obj.value("utilization_pct").toDouble());
    s.set_context_length(static_cast<int64_t>(obj.value("context_length").toDouble()));
    s.set_usable_context(static_cast<int64_t>(obj.value("usable_context").toDouble()));
    if (obj.contains("release_date") && !obj.value("release_date").isNull())
        s.set_release_date(obj.value("release_date").toString().toStdString());
    s.set_category(obj.value("category").toString().toStdString());

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
    if (s.hf_repo().empty())
    {
        for (const auto& candidate : {name, QString::fromStdString(s.id())})
        {
            if (candidate.contains("-GGUF", Qt::CaseInsensitive))
            {
                s.set_hf_repo(candidate.toStdString());
                break;
            }
        }
    }
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

QString gguf_base_name(QString model_id)
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
                               "-FP16",
                               "-bf16",
                               "-BF16",
                               "-NVFP4A16"};
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
        static const QRegularExpression trailing_patterns[] = {
            QRegularExpression{R"(-OptQ-\d+bit$)", QRegularExpression::CaseInsensitiveOption},
            QRegularExpression{R"(-aQ[\d.]+$)", QRegularExpression::CaseInsensitiveOption},
        };
        for (const auto& pattern : trailing_patterns)
        {
            const auto match = pattern.match(model_id);
            if (match.hasMatch())
            {
                model_id.chop(match.capturedLength(0));
                stripped = true;
                break;
            }
        }
    }
    return model_id;
}

void append_unique_query(QStringList& queries, const QString& query)
{
    const auto trimmed = query.trimmed();
    if (!trimmed.isEmpty() && !queries.contains(trimmed))
        queries << trimmed;
}

QStringList download_resolution_queries(const QString& model_id, const QString& hf_repo_hint)
{
    QStringList queries;
    append_unique_query(queries, hf_repo_hint);
    append_unique_query(queries, model_id);

    const auto base = gguf_base_name(model_id);
    append_unique_query(queries, base);

    if (!base.isEmpty() && !base.contains("-GGUF", Qt::CaseInsensitive))
    {
        append_unique_query(queries, base + "-GGUF");
        if (model_id.contains('/'))
        {
            const auto org = model_id.section('/', 0, 0);
            append_unique_query(queries, org + "/" + base + "-GGUF");
        }
        if (base.startsWith("NVIDIA-", Qt::CaseInsensitive))
            append_unique_query(queries, "nvidia/" + base + "-GGUF");
    }

    if (model_id.contains("-GGUF", Qt::CaseInsensitive))
        append_unique_query(queries, model_id);

    return queries;
}

void enrich_gguf_repo_hints(std::vector<mp::ModelSuggestion>& models)
{
    for (auto& model : models)
    {
        if (!model.hf_repo().empty())
            continue;

        for (const auto& candidate : {QString::fromStdString(model.name()),
                                       QString::fromStdString(model.id())})
        {
            if (candidate.contains("-GGUF", Qt::CaseInsensitive))
            {
                model.set_hf_repo(candidate.toStdString());
                break;
            }
        }
        if (!model.hf_repo().empty())
            continue;

        const auto id = QString::fromStdString(model.id());
        const auto base = gguf_base_name(id);
        if (base.isEmpty() || base.contains("-GGUF", Qt::CaseInsensitive))
            continue;
        if (base.startsWith("NVIDIA-", Qt::CaseInsensitive))
            model.set_hf_repo(QString("nvidia/%1-GGUF").arg(base).toStdString());
    }
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

QStringList hardware_args(const mp::MemorySize& available_ram, int cpu_cores, bool unified_memory)
{
    QStringList args{"--json",
                     "--no-dashboard",
                     "--ram",
                     ram_flag(available_ram),
                     "--cpu-cores",
                     QString::number(std::max(cpu_cores, 1))};
    if (unified_memory)
        args << "--memory" << ram_flag(available_ram);
    return args;
}

void append_recommend_runtime_filters(QStringList& args, const std::string& runtime)
{
    auto rt = QString::fromStdString(runtime).toLower();
    if (!mp::enable_mlx_backend && rt.contains("mlx"))
        rt = "llamacpp";
    if (rt.contains("mlx"))
        args << "--runtime" << "mlx";
    else if (!rt.isEmpty())
        args << "--force-runtime" << "llamacpp";
}

void append_recommend_catalog_filters(QStringList& args,
                                      const std::string& use_case,
                                      const std::string& min_fit)
{
    if (!use_case.empty())
        args << "--use-case" << QString::fromStdString(use_case);
    if (!min_fit.empty())
        args << "--min-fit" << QString::fromStdString(min_fit);
}

void append_fit_cli_filters(QStringList& args, const std::string& min_fit)
{
    if (min_fit == "perfect")
        args << "--perfect";
}

std::vector<mp::ModelSuggestion> models_from_json(const QJsonDocument& doc)
{
    QJsonArray models_json;
    if (doc.isObject())
        models_json = doc.object().value("models").toArray();
    else if (doc.isArray())
        models_json = doc.array();

    std::vector<mp::ModelSuggestion> models;
    for (const auto& item : models_json)
    {
        if (item.isObject())
            models.push_back(suggestion_from_json(item.toObject()));
    }
    return models;
}

bool model_matches_query(const mp::ModelSuggestion& model, const QString& query)
{
    const auto trimmed = query.trimmed();
    if (trimmed.isEmpty())
        return true;

    const auto haystack = QStringList{
                                QString::fromStdString(model.name()),
                                QString::fromStdString(model.provider()),
                                QString::fromStdString(model.id()),
                                QString::fromStdString(model.hf_repo()),
                            }
                                .join(' ')
                                .toLower();

    const auto tokens =
        trimmed.toLower().split(QRegularExpression{R"(\s+)"}, Qt::SkipEmptyParts);
    for (const auto& token : tokens)
    {
        if (!haystack.contains(token))
            return false;
    }
    return true;
}

bool is_too_tight_fit(const mp::ModelSuggestion& model)
{
    const auto fit = QString::fromStdString(model.fit_level()).toLower();
    return fit.contains("too") || fit.contains("tight") || fit.contains("incompat");
}

bool model_matches_runtime(const mp::ModelSuggestion& model, const std::string& runtime)
{
    if (runtime.empty())
        return true;
    const auto model_rt = QString::fromStdString(model.runtime()).toLower();
    if (model_rt.isEmpty())
        return true;
    auto rt = QString::fromStdString(runtime).toLower();
    if (!mp::enable_mlx_backend && rt.contains("mlx"))
        rt = "llamacpp";
    if (rt.contains("mlx"))
        return model_rt.contains("mlx");
    if (rt.contains("llama"))
        return model_rt.contains("llama");
    return true;
}

bool model_matches_use_case(const mp::ModelSuggestion& model, const std::string& use_case)
{
    if (use_case.empty())
        return true;
    const auto model_use = QString::fromStdString(model.use_case()).toLower();
    if (model_use.isEmpty())
        return true;
    return model_use == QString::fromStdString(use_case).toLower();
}

bool model_matches_min_fit(const mp::ModelSuggestion& model, const std::string& min_fit)
{
    if (min_fit.empty())
        return true;
    const auto fit = QString::fromStdString(model.fit_level()).toLower();
    if (fit.isEmpty())
        return true;
    if (min_fit == "perfect")
        return fit.contains("perfect");
    if (min_fit == "good")
        return fit.contains("perfect") || fit.contains("good");
    if (min_fit == "marginal")
        return !is_too_tight_fit(model);
    return true;
}

void merge_models(std::vector<mp::ModelSuggestion>& into, const std::vector<mp::ModelSuggestion>& extra)
{
    for (const auto& model : extra)
    {
        const auto id = model.id();
        const auto found = std::find_if(into.begin(), into.end(), [&](const mp::ModelSuggestion& existing) {
            return existing.id() == id;
        });
        if (found == into.end())
            into.push_back(model);
    }
}

void enrich_models(std::vector<mp::ModelSuggestion>& into, const std::vector<mp::ModelSuggestion>& fit)
{
    auto repo_suffix = [](const std::string& id) {
        const auto qid = QString::fromStdString(id).toLower();
        return qid.contains('/') ? qid.section('/', -1) : qid;
    };

    auto find_fit_match = [&](const mp::ModelSuggestion& model) -> const mp::ModelSuggestion* {
        for (const auto& candidate : fit)
        {
            if (candidate.id() == model.id())
                return &candidate;
        }
        const auto suffix = repo_suffix(model.id());
        if (suffix.size() < 4)
            return nullptr;
        for (const auto& candidate : fit)
        {
            if (repo_suffix(candidate.id()) == suffix)
                return &candidate;
        }
        return nullptr;
    };

    for (auto& model : into)
    {
        if (model.memory_required_gb() > 0 && !model.runtime().empty())
            continue;
        const auto* match = find_fit_match(model);
        if (!match)
            continue;
        const auto id = model.id();
        const auto name = model.name();
        model = *match;
        if (!id.empty())
            model.set_id(id);
        if (!name.empty())
            model.set_name(name);
    }
}

int model_metadata_score(const mp::ModelSuggestion& model)
{
    int score = 0;
    if (!model.parameter_count().empty())
        score += 1;
    if (model.memory_required_gb() > 0)
        score += 2;
    if (!model.runtime().empty())
        score += 2;
    if (!model.best_quant().empty())
        score += 1;
    if (!model.fit_level().empty())
        score += 1;
    return score;
}

void sort_by_metadata(std::vector<mp::ModelSuggestion>& models)
{
    std::stable_sort(models.begin(), models.end(), [](const mp::ModelSuggestion& a, const mp::ModelSuggestion& b) {
        if (a.score() != b.score())
            return a.score() > b.score();
        const auto score_a = model_metadata_score(a);
        const auto score_b = model_metadata_score(b);
        if (score_a != score_b)
            return score_a > score_b;
        return a.name() < b.name();
    });
}

std::vector<mp::ModelSuggestion> parse_search_table(const QString& text)
{
    std::vector<mp::ModelSuggestion> models;
    static const QRegularExpression line_repo_re{
        R"(^\s*([\w\.\-]+/[\w\.\-]+|[A-Za-z][\w\.\-]*(?:-[\w\.]+)+)\s+)"};
    static const QRegularExpression hf_id_re{
        R"((?:^|[\s│|])([\w\.\-]+/[\w\.\-]+|[A-Za-z][\w\.\-]*(?:-[\w\.]+)+)(?:[\s│|]|$))"};
    QSet<QString> seen;
    for (const auto& line : text.split('\n'))
    {
        const auto trimmed = line.trimmed();
        if (trimmed.isEmpty() || trimmed.startsWith('-') || trimmed.startsWith("Repository") ||
            trimmed.startsWith("No local models") || trimmed.startsWith("To download") ||
            trimmed.startsWith("Tip:"))
            continue;

        QString captured;
        const auto line_match = line_repo_re.match(trimmed);
        if (line_match.hasMatch())
            captured = line_match.captured(1).trimmed();

        if (captured.isEmpty())
        {
            const auto id_match = hf_id_re.match(trimmed);
            if (id_match.hasMatch())
                captured = id_match.captured(1).trimmed();
        }

        if (captured.isEmpty() || seen.contains(captured))
            continue;
        seen.insert(captured);
        mp::ModelSuggestion s;
        s.set_id(captured.toStdString());
        s.set_name(captured.toStdString());
        if (captured.contains('/'))
            s.set_provider(captured.section('/', 0, 0).toStdString());
        models.push_back(std::move(s));
    }
    return models;
}

std::vector<mp::ModelSuggestion> run_fit_catalog(const QString& binary,
                                                 const mp::MemorySize& available_ram,
                                                 int cpu_cores,
                                                 bool unified_memory,
                                                 const std::string& min_fit,
                                                 int fit_n)
{
    auto args = hardware_args(available_ram, cpu_cores, unified_memory);
    args << "fit" << "--limit" << QString::number(fit_n);
    append_fit_cli_filters(args, min_fit);
    mpl::info(category, "running {} {}", binary, args.join(' '));
    return models_from_json(parse_json_payload(run_llmfit(binary, args, 120000)));
}

std::vector<mp::ModelSuggestion> run_search_catalog(const QString& binary,
                                                    const mp::MemorySize& available_ram,
                                                    int cpu_cores,
                                                    bool unified_memory,
                                                    const QString& query)
{
    auto search_args = hardware_args(available_ram, cpu_cores, unified_memory);
    search_args << "search" << query;
    mpl::info(category, "running {} {}", binary, search_args.join(' '));
    const auto raw = run_llmfit(binary, search_args, 120000);
    try
    {
        return models_from_json(parse_json_payload(raw));
    }
    catch (const std::exception&)
    {
        return parse_search_table(QString::fromUtf8(raw));
    }
}

std::vector<mp::ModelSuggestion> slice_models(std::vector<mp::ModelSuggestion> models,
                                              int offset,
                                              int limit)
{
    if (offset > 0)
    {
        if (offset >= static_cast<int>(models.size()))
            return {};
        models.erase(models.begin(), models.begin() + offset);
    }
    if (limit > 0 && static_cast<int>(models.size()) > limit)
        models.resize(static_cast<size_t>(limit));
    return models;
}
} // namespace

mp::LlmfitAdvisor::LlmfitAdvisor(QString managed_tools_dir)
    : managed_tools_dir{std::move(managed_tools_dir)}
{
}

QString mp::LlmfitAdvisor::binary_path() const
{
    return llm::locate_binary(mp::llmfit_env_var,
                              {"llmfit"},
                              managed_tools_dir,
                              QString::fromUtf8(llm::tool_llmfit));
}

std::string mp::LlmfitAdvisor::missing_binary_hint() const
{
    return "llmfit is not installed. Use Models → Backends → Install, or set ELP_LLMFIT "
           "to the binary path. Loaded models and the OpenAI API still work.";
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
    auto args = hardware_args(available_ram, cpu_cores, unified_memory);
    args << "recommend" << "--limit" << QString::number(limit > 0 ? limit : 10);

    append_recommend_runtime_filters(args, runtime);
    append_recommend_catalog_filters(args, use_case, min_fit);

    mpl::info(category, "running {} {}", binary, args.join(' '));
    const auto doc = parse_json_payload(run_llmfit(binary, args, 60000));
    auto models = models_from_json(doc);
    enrich_gguf_repo_hints(models);

    cache = CacheEntry{available_ram.in_bytes(), runtime, use_case, now, models};
    return models;
}

std::vector<mp::ModelSuggestion> mp::LlmfitAdvisor::browse(MemorySize available_ram,
                                                             int cpu_cores,
                                                             const std::string& runtime,
                                                             const std::string& use_case,
                                                             const std::string& min_fit,
                                                             const std::string& query,
                                                             int limit,
                                                             int offset,
                                                             bool include_too_tight,
                                                             bool unified_memory)
{
    const auto binary = binary_path();
    if (binary.isEmpty())
        throw std::runtime_error(missing_binary_hint());

    std::lock_guard lock{mutex};
    const auto q = QString::fromStdString(query).trimmed();
    const int fetch_limit = std::max(limit + offset, limit);
    const int fit_n = q.isEmpty() ? std::max(fetch_limit, 500) : 2000;

    std::vector<ModelSuggestion> models;
    if (q.isEmpty())
    {
        try
        {
            models = run_fit_catalog(binary,
                                     available_ram,
                                     cpu_cores,
                                     unified_memory,
                                     min_fit,
                                     fit_n);
        }
        catch (const std::exception& e)
        {
            mpl::warn(category, "llmfit fit browse failed: {}", e.what());
        }
    }
    else
    {
        std::vector<ModelSuggestion> fit_models;
        try
        {
            fit_models = run_fit_catalog(binary,
                                         available_ram,
                                         cpu_cores,
                                         unified_memory,
                                         min_fit,
                                         2000);
            for (const auto& fit_model : fit_models)
            {
                if (!model_matches_query(fit_model, q))
                    continue;
                models.push_back(fit_model);
            }
        }
        catch (const std::exception& e)
        {
            mpl::warn(category, "llmfit fit enrichment for '{}' failed: {}", query, e.what());
        }

        try
        {
            auto searched = run_search_catalog(binary, available_ram, cpu_cores, unified_memory, q);
            enrich_models(searched, fit_models);
            merge_models(models, searched);
        }
        catch (const std::exception& e)
        {
            mpl::warn(category, "llmfit search '{}' failed: {}", query, e.what());
        }
    }

    std::vector<ModelSuggestion> filtered;
    filtered.reserve(models.size());
    for (auto& model : models)
    {
        if (!model_matches_query(model, q))
            continue;
        if (!model_matches_runtime(model, runtime))
            continue;
        if (!model_matches_use_case(model, use_case))
            continue;
        if (!model_matches_min_fit(model, min_fit))
            continue;
        if (!include_too_tight && is_too_tight_fit(model))
            continue;
        filtered.push_back(std::move(model));
    }

    sort_by_metadata(filtered);
    enrich_gguf_repo_hints(filtered);

    return slice_models(std::move(filtered), offset, limit > 0 ? limit : 100);
}

std::optional<mp::ResolvedGguf> mp::LlmfitAdvisor::resolve(const std::string& model_id,
                                                           const std::string& quant,
                                                           const std::string& hf_repo)
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

    const auto queries = download_resolution_queries(QString::fromStdString(model_id),
                                                     QString::fromStdString(hf_repo));
    for (const auto& query : queries)
    {
        if (auto resolved = try_list(query))
            return resolved;
    }
    return std::nullopt;
}
