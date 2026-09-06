import '../../providers.dart';
import 'model_branding.dart';

/// Hand-picked models shown in the simple catalog before llmfit enrichment.
class CuratedModelPick {
  const CuratedModelPick({
    required this.query,
    required this.displayName,
    required this.provider,
    required this.category,
    required this.blurb,
  });

  /// Substring matched against llmfit id / name / hf_repo.
  final String query;
  final String displayName;
  final String provider;
  final String category;
  final String blurb;
}

/// Big-name shortlist — order is the preferred card order.
const kCuratedTopPicks = <CuratedModelPick>[
  CuratedModelPick(
    query: 'Gemma-2-9B',
    displayName: 'Gemma 2 9B',
    provider: 'Google',
    category: 'chat',
    blurb: 'Google open weights with strong instruction quality.',
  ),
  CuratedModelPick(
    query: 'Gemma-2-2B',
    displayName: 'Gemma 2 2B',
    provider: 'Google',
    category: 'chat',
    blurb: 'Small Gemma for fast local chat on modest hosts.',
  ),
  CuratedModelPick(
    query: 'Nemotron',
    displayName: 'Nemotron Nano',
    provider: 'NVIDIA',
    category: 'chat',
    blurb: 'NVIDIA nano-class model tuned for efficient local runs.',
  ),
  CuratedModelPick(
    query: 'DeepSeek-R1-Distill-Qwen-7B',
    displayName: 'DeepSeek R1 Distill 7B',
    provider: 'DeepSeek',
    category: 'reasoning',
    blurb: 'Popular distilled reasoning model that still fits many machines.',
  ),
  CuratedModelPick(
    query: 'DeepSeek-R1-Distill-Llama-8B',
    displayName: 'DeepSeek R1 Distill 8B',
    provider: 'DeepSeek',
    category: 'reasoning',
    blurb: 'Llama-based DeepSeek distill for local reasoning workloads.',
  ),
  CuratedModelPick(
    query: 'Llama-3.1-8B-Instruct',
    displayName: 'Llama 3.1 8B',
    provider: 'Meta',
    category: 'chat',
    blurb: 'Meta’s widely used 8B instruct model for general chat.',
  ),
  CuratedModelPick(
    query: 'Llama-3.2-3B-Instruct',
    displayName: 'Llama 3.2 3B',
    provider: 'Meta',
    category: 'chat',
    blurb: 'Fast, lightweight Meta model for smaller hosts.',
  ),
  CuratedModelPick(
    query: 'Phi-4-mini',
    displayName: 'Phi-4 Mini',
    provider: 'Microsoft',
    category: 'chat',
    blurb: 'Compact Microsoft model with strong reasoning for its size.',
  ),
  CuratedModelPick(
    query: 'Phi-4',
    displayName: 'Phi-4',
    provider: 'Microsoft',
    category: 'reasoning',
    blurb: 'Higher-quality Microsoft reasoning when the host has room.',
  ),
  CuratedModelPick(
    query: 'Mistral-7B-Instruct',
    displayName: 'Mistral 7B Instruct',
    provider: 'Mistral',
    category: 'chat',
    blurb: 'A classic 7B instruct model from Mistral AI.',
  ),
  CuratedModelPick(
    query: 'Qwen2.5-Coder-7B-Instruct',
    displayName: 'Qwen2.5 Coder 7B',
    provider: 'Qwen',
    category: 'coding',
    blurb: 'One of the most used local coding assistants.',
  ),
  CuratedModelPick(
    query: 'Qwen2.5-7B-Instruct',
    displayName: 'Qwen2.5 7B Instruct',
    provider: 'Qwen',
    category: 'chat',
    blurb: 'Popular Alibaba Qwen instruct model for everyday tasks.',
  ),
  CuratedModelPick(
    query: 'granite-3.1-8b-instruct',
    displayName: 'Granite 3.1 8B',
    provider: 'IBM',
    category: 'chat',
    blurb: 'IBM’s enterprise-oriented open instruct model.',
  ),
  CuratedModelPick(
    query: 'SmolLM2-1.7B-Instruct',
    displayName: 'SmolLM2 1.7B',
    provider: 'Hugging Face',
    category: 'chat',
    blurb: 'Tiny Hugging Face model — a good first load on constrained hosts.',
  ),
];

const kTopPicksTargetCount = 14;

String normalizeModelKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

bool modelMatchesCurated(ModelSuggestion model, CuratedModelPick pick) {
  final needle = normalizeModelKey(pick.query);
  if (needle.isEmpty) return false;
  final haystacks = [
    model.id,
    model.name,
    model.hfRepo,
    model.filename,
  ].map(normalizeModelKey);
  return haystacks.any((h) => h.contains(needle));
}

ModelSuggestion stubFromCurated(CuratedModelPick pick) {
  return ModelSuggestion(
    id: pick.query,
    name: pick.displayName,
    provider: pick.provider,
    category: pick.category,
    useCase: pick.category,
  );
}

ModelSuggestion enrichWithCurated(
  ModelSuggestion model,
  CuratedModelPick pick,
) {
  return ModelSuggestion(
    id: model.id.isNotEmpty ? model.id : pick.query,
    name: model.name.isNotEmpty ? model.name : pick.displayName,
    provider: model.provider.isNotEmpty ? model.provider : pick.provider,
    parameterCount: model.parameterCount,
    fitLevel: model.fitLevel,
    score: model.score,
    bestQuant: model.bestQuant,
    memoryRequiredGb: model.memoryRequiredGb,
    estimatedTps: model.estimatedTps,
    runtime: model.runtime,
    useCase: model.useCase.isNotEmpty ? model.useCase : pick.category,
    hfRepo: model.hfRepo,
    filename: model.filename,
    diskSizeGb: model.diskSizeGb,
    runMode: model.runMode,
    utilizationPct: model.utilizationPct,
    contextLength: model.contextLength,
    usableContext: model.usableContext,
    releaseDate: model.releaseDate,
    category: model.category.isNotEmpty ? model.category : pick.category,
    path: model.path,
  );
}

ModelSuggestion? bestMatchForCurated(
  List<ModelSuggestion> pool,
  CuratedModelPick pick,
) {
  final matches = pool.where((m) => modelMatchesCurated(m, pick)).toList();
  if (matches.isEmpty) return null;
  matches.sort((a, b) {
    final scoreCmp = b.score.compareTo(a.score);
    if (scoreCmp != 0) return scoreCmp;
    return a.id.length.compareTo(b.id.length);
  });
  return matches.first;
}

bool _isBigNameSuggestion(ModelSuggestion model) {
  return isKnownModelProvider(model.provider) ||
      isKnownModelProvider(model.id) ||
      isKnownModelProvider(model.name) ||
      isKnownModelProvider(model.hfRepo);
}

/// Merge curated big-name picks with llmfit recommend + fit results.
///
/// Extra slots are filled only from known providers (Google, Meta, NVIDIA…).
List<ModelSuggestion> mergeTopPicks({
  required List<ModelSuggestion> recommended,
  required List<ModelSuggestion> fitted,
  int targetCount = kTopPicksTargetCount,
}) {
  final pool = <ModelSuggestion>[...recommended, ...fitted];
  final result = <ModelSuggestion>[];
  final used = <String>{};

  void addUnique(ModelSuggestion model) {
    final key = normalizeModelKey(model.id.isNotEmpty ? model.id : model.name);
    if (key.isEmpty || used.contains(key)) return;
    used.add(key);
    result.add(model);
  }

  for (final pick in kCuratedTopPicks) {
    final match = bestMatchForCurated(pool, pick);
    addUnique(
        match != null ? enrichWithCurated(match, pick) : stubFromCurated(pick));
    if (result.length >= targetCount) {
      return result;
    }
  }

  final fillers = [...recommended, ...fitted]
      .where(_isBigNameSuggestion)
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  for (final model in fillers) {
    if (result.length >= targetCount) break;
    addUnique(model);
  }

  return result;
}

String topPickBlurb(ModelSuggestion model) {
  for (final pick in kCuratedTopPicks) {
    if (modelMatchesCurated(model, pick) ||
        normalizeModelKey(model.id) == normalizeModelKey(pick.query) ||
        normalizeModelKey(model.name) == normalizeModelKey(pick.displayName)) {
      return pick.blurb;
    }
  }
  final fit = model.fitLevel.trim();
  final params = model.parameterCount.trim();
  final parts = <String>[
    if (params.isNotEmpty) params,
    if (fit.isNotEmpty) 'Fit: $fit',
    if (model.bestQuant.isNotEmpty) model.bestQuant,
  ];
  if (parts.isEmpty) {
    return 'Suggested for this host by llmfit.';
  }
  return parts.join(' · ');
}
