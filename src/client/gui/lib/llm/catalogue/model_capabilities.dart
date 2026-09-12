import 'package:flutter/material.dart';

import '../../brand.dart';
import '../../providers.dart';

/// Capability / modality tags shown on catalog, downloaded, and running models.
enum ModelCapability {
  multimodal,
  tools,
  coding,
  reasoning,
  chat,
  embedding,
}

extension ModelCapabilityLabel on ModelCapability {
  String get label => switch (this) {
        ModelCapability.multimodal => 'multimodal',
        ModelCapability.tools => 'tools',
        ModelCapability.coding => 'coding',
        ModelCapability.reasoning => 'reasoning',
        ModelCapability.chat => 'chat',
        ModelCapability.embedding => 'embedding',
      };
}

/// Known models / families with tool-calling or MCP-friendly instruct APIs.
const _toolsFamilies = <String>[
  'qwen2.5',
  'qwen2.5-coder',
  'qwen3',
  'llama-3.1',
  'llama-3.2',
  'llama-3.3',
  'mistral-7b-instruct',
  'mistral-small',
  'mistral-nemo',
  'mixtral',
  'phi-4',
  'nemotron',
  'granite',
  'command-r',
  'hermes',
  'functionary',
  'gorilla',
  'toolace',
];

const _chatFamilies = <String>[
  'gemma',
  'llama',
  'mistral',
  'phi-',
  'qwen',
  'nemotron',
  'granite',
  'smollm',
  'deepseek',
  'yi-',
  'falcon',
];

const _multimodalFamilies = <String>[
  'llava',
  'pixtral',
  'qwen2-vl',
  'qwen2.5-vl',
  'qwen-vl',
  'internvl',
  'minicpm-v',
  'phi-3.5-vision',
  'phi-4-multimodal',
  'gemma-3',
  'llama-3.2-vision',
  'llama-4',
  'molmo',
  'idefics',
  'cogvlm',
  'nemotron-vl',
];

String _haystack({
  required String id,
  required String name,
  required String useCase,
  required String category,
  required String hfRepo,
}) {
  return '$id $name $useCase $category $hfRepo'
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9.+\-]+'), ' ');
}

bool _containsAny(String hay, Iterable<String> needles) =>
    needles.any(hay.contains);

/// Derive ordered, de-duplicated capability tags for a model.
List<ModelCapability> modelCapabilities({
  String id = '',
  String name = '',
  String useCase = '',
  String category = '',
  String hfRepo = '',
}) {
  final hay = _haystack(
    id: id,
    name: name,
    useCase: useCase,
    category: category,
    hfRepo: hfRepo,
  );
  final use = useCase.toLowerCase().trim();
  final cat = category.toLowerCase().trim();
  final primary = use.isNotEmpty ? use : cat;

  final tags = <ModelCapability>{};

  void addFromPrimary(String value) {
    if (value.contains('multimodal') || value.contains('vision')) {
      tags.add(ModelCapability.multimodal);
    }
    if (value.contains('coding') || value.contains('code')) {
      tags.add(ModelCapability.coding);
    }
    if (value.contains('reason')) {
      tags.add(ModelCapability.reasoning);
    }
    if (value.contains('embed')) {
      tags.add(ModelCapability.embedding);
    }
    if (value.contains('chat') || value.contains('instruct')) {
      tags.add(ModelCapability.chat);
    }
    if (value.contains('tool') || value.contains('mcp') || value.contains('agent')) {
      tags.add(ModelCapability.tools);
    }
  }

  addFromPrimary(primary);

  if (_containsAny(hay, _multimodalFamilies) ||
      _containsAny(hay, const [
        'vision',
        'multimodal',
        '-vl-',
        'vl-',
        'vl.',
      ])) {
    tags.add(ModelCapability.multimodal);
  }

  if (_containsAny(hay, const [
        'coder',
        'code-',
        '-code',
        'codestral',
        'starcoder',
        'deepseek-coder',
      ]) ||
      primary.contains('coding')) {
    tags.add(ModelCapability.coding);
  }

  if (_containsAny(hay, const [
        'reason',
        'r1',
        'qwq',
        'magistral',
        'o1-',
        'thinking',
      ])) {
    tags.add(ModelCapability.reasoning);
  }

  if (_containsAny(hay, const ['embed', 'e5-', 'bge-', 'gte-'])) {
    tags.add(ModelCapability.embedding);
  }

  if (_containsAny(hay, _toolsFamilies) ||
      _containsAny(hay, const [
        'tool',
        'functionary',
        'mcp',
        'agent',
        'function-call',
        'function_call',
      ])) {
    tags.add(ModelCapability.tools);
  }

  if (_containsAny(hay, const ['instruct', 'chat', '-it']) ||
      primary == 'chat' ||
      primary == 'general' ||
      _containsAny(hay, _chatFamilies)) {
    tags.add(ModelCapability.chat);
  }

  // Embedding-only models should not also look like chat.
  if (tags.contains(ModelCapability.embedding)) {
    tags.remove(ModelCapability.chat);
  }

  // Downloaded vault entries often lack use_case — still show a chat tag
  // when we clearly have a model identity.
  if (tags.isEmpty &&
      (id.trim().isNotEmpty ||
          name.trim().isNotEmpty ||
          hfRepo.trim().isNotEmpty)) {
    tags.add(ModelCapability.chat);
  }

  const order = ModelCapability.values;
  final sorted = order.where(tags.contains).toList();
  return sorted;
}

List<ModelCapability> _mergeCapabilities(Iterable<List<ModelCapability>> sets) {
  final tags = <ModelCapability>{};
  for (final set in sets) {
    tags.addAll(set);
  }
  return ModelCapability.values.where(tags.contains).toList();
}

bool _idsOverlap(String a, String b) {
  final left = a.toLowerCase().trim();
  final right = b.toLowerCase().trim();
  if (left.isEmpty || right.isEmpty) return false;
  return left == right || left.contains(right) || right.contains(left);
}

List<ModelCapability> capabilitiesForSuggestion(
  ModelSuggestion model, {
  Iterable<ModelSuggestion> hints = const [],
}) {
  final direct = modelCapabilities(
    id: model.id,
    name: model.name,
    useCase: model.useCase,
    category: model.category,
    hfRepo: model.hfRepo,
  );

  final fromHints = <List<ModelCapability>>[];
  for (final hint in hints) {
    if (_idsOverlap(model.id, hint.id) ||
        _idsOverlap(model.name, hint.name) ||
        _idsOverlap(model.hfRepo, hint.hfRepo) ||
        _idsOverlap(model.id, hint.name) ||
        _idsOverlap(model.name, hint.id)) {
      fromHints.add(modelCapabilities(
        id: hint.id,
        name: hint.name,
        useCase: hint.useCase,
        category: hint.category,
        hfRepo: hint.hfRepo,
      ));
    }
  }

  if (fromHints.isEmpty) return direct;
  return _mergeCapabilities([direct, ...fromHints]);
}

List<ModelCapability> capabilitiesForLoaded(
  LoadedModelInfo model, {
  Iterable<ModelSuggestion> hints = const [],
}) {
  for (final hint in hints) {
    if (_idsOverlap(model.modelId, hint.id) ||
        _idsOverlap(model.modelId, hint.name) ||
        _idsOverlap(model.openaiId, hint.id)) {
      final fromHint = modelCapabilities(
        id: hint.id,
        name: hint.name,
        useCase: hint.useCase,
        category: hint.category,
        hfRepo: hint.hfRepo,
      );
      if (fromHint.isNotEmpty) return fromHint;
    }
  }
  return modelCapabilities(id: model.modelId, name: model.openaiId);
}

class ModelCapabilityChips extends StatelessWidget {
  const ModelCapabilityChips({
    required this.capabilities,
    this.compact = false,
    this.maxTags = 4,
    super.key,
  });

  final List<ModelCapability> capabilities;
  final bool compact;
  final int maxTags;

  @override
  Widget build(BuildContext context) {
    if (capabilities.isEmpty) return const SizedBox.shrink();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final shown = capabilities.take(maxTags).toList();

    return Wrap(
      spacing: compact ? 4 : 6,
      runSpacing: compact ? 4 : 6,
      children: [
        for (final tag in shown)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 8,
              vertical: compact ? 2 : 3,
            ),
            decoration: BoxDecoration(
              color: onSurface.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Brand.radiusPill),
              border: Border.all(color: onSurface.withValues(alpha: 0.12)),
            ),
            child: Text(
              tag.label,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
      ],
    );
  }
}
