import 'dart:math';

import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intersperse/intersperse.dart';

import '../brand.dart';
import '../catalogue/catalogue_surface.dart';
import '../confirmation_dialog.dart';
import '../copyable_text.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../tooltip.dart';
import '../vm_table/table.dart' as vmtable;
import '../widgets/card_action_row.dart';
import '../widgets/launchpad_button.dart';
import 'catalogue/model_branding.dart';
import 'catalogue/model_capabilities.dart';
import 'llm_load.dart';
import 'providers.dart';

/// One vault row for a model (format + quant), used when grouping multi-downloads.
class CachedModelArtifact {
  const CachedModelArtifact(this.model);

  final ModelSuggestion model;

  String get format {
    final raw = model.format.trim().toLowerCase();
    if (raw.isNotEmpty) return raw;
    final path = model.path.trim();
    final lower = path.toLowerCase();
    if (lower.endsWith('.gguf')) return 'gguf';
    final file = model.filename.trim().toLowerCase();
    if (file.endsWith('.gguf')) return 'gguf';
    // Local MLX/HF vault snapshots are directories (often absolute) without .gguf.
    if (path.isNotEmpty) return 'mlx';
    return 'gguf';
  }

  String get formatLabel => switch (format) {
        'mlx' => 'MLX',
        'hf' => 'HF',
        'onnx' => 'ONNX',
        _ => 'GGUF',
      };

  String get quant {
    if (format == 'gguf') {
      final fromName = _ggufQuantFromName(
        model.filename.isNotEmpty ? model.filename : model.path,
      );
      if (fromName.isNotEmpty) return fromName;
    }
    return model.bestQuant;
  }

  String get sizeLabel {
    final gb = model.diskSizeGb > 0 ? model.diskSizeGb : model.memoryRequiredGb;
    if (gb <= 0) return '';
    return '${gb.toStringAsFixed(1)} GiB';
  }

  String get summary {
    final parts = <String>[
      formatLabel,
      if (quant.isNotEmpty) quant,
      if (sizeLabel.isNotEmpty) sizeLabel,
    ];
    return parts.join(' · ');
  }
}

/// Downloaded model card model: one logical id with one or more artifacts.
class CachedModelGroup {
  CachedModelGroup({required this.id, required List<ModelSuggestion> artifacts})
      : artifacts = [
          for (final model in artifacts) CachedModelArtifact(model),
        ]..sort((a, b) {
            final byFormat = a.formatLabel.compareTo(b.formatLabel);
            if (byFormat != 0) return byFormat;
            return a.quant.compareTo(b.quant);
          });

  final String id;
  final List<CachedModelArtifact> artifacts;

  ModelSuggestion get primary => artifacts.first.model;

  bool get hasMultiple => artifacts.length > 1;

  String get title {
    final name = primary.name;
    return name.isEmpty ? id : name;
  }

  /// Prefer a GGUF artifact for load defaults, else the first entry.
  ModelSuggestion get loadSeed {
    for (final art in artifacts) {
      if (art.format == 'gguf') return art.model;
    }
    return primary;
  }
}

List<CachedModelGroup> groupCachedModels(Iterable<ModelSuggestion> models) {
  final byId = <String, List<ModelSuggestion>>{};
  for (final model in models) {
    final id = model.id.isEmpty ? model.path : model.id;
    byId.putIfAbsent(id, () => []).add(model);
  }
  final groups = [
    for (final entry in byId.entries)
      CachedModelGroup(id: entry.key, artifacts: entry.value),
  ];
  groups.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return groups;
}

final _ggufQuantRe = RegExp(
  r'-((?:IQ|Q|F|BF)\d+(?:_[A-Za-z0-9]+)*)\.gguf$',
  caseSensitive: false,
);

String _ggufQuantFromName(String name) {
  final base = name.split('/').last;
  final match = _ggufQuantRe.firstMatch(base);
  return match?.group(1) ?? '';
}

Future<void> showCachedModelDetails(
  BuildContext context,
  CachedModelGroup group, {
  Iterable<ModelSuggestion> hints = const [],
}) async {
  final l10n = AppLocalizations.of(context)!;
  final model = group.primary;
  final rows = <(String, String)>[
    if (model.id.isNotEmpty) (l10n.modelsDetailId, model.id),
    if (model.provider.isNotEmpty) (l10n.modelsDetailProvider, model.provider),
    if (model.parameterCount.isNotEmpty)
      (l10n.modelsDetailParams, model.parameterCount),
  ];
  final capabilities = capabilitiesForSuggestion(model, hints: hints);

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(group.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (capabilities.isNotEmpty) ...[
              ModelCapabilityChips(capabilities: capabilities),
              const SizedBox(height: 16),
            ],
            for (final row in rows) ...[
              Text(
                row.$1,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 2),
              CopyableText(
                row.$2,
                style: const TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              l10n.modelsDetailArtifacts,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(ctx)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 8),
            for (final art in group.artifacts) ...[
              Text(
                art.summary,
                style: const TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (art.model.hfRepo.isNotEmpty)
                CopyableText(
                  art.model.hfRepo,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 12,
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
              if (art.model.filename.isNotEmpty)
                CopyableText(
                  art.model.filename,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 12,
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
              if (art.model.path.isNotEmpty && art.model.path != art.model.hfRepo)
                CopyableText(
                  art.model.path,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 12,
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.commonClose),
        ),
      ],
    ),
  );
}

class LlmActiveDownloadsTable extends ConsumerWidget {
  final List<ModelDownloadJob> jobs;

  const LlmActiveDownloadsTable({required this.jobs, super.key});

  static Widget _header(String name) {
    return vmtable.TableHeader.defaultHeaderBuilder(name);
  }

  static Widget _cell(String text) {
    return Text(
      text.isEmpty ? '-' : text,
      style: const TextStyle(fontSize: 10),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final headers = <vmtable.TableHeader<ModelDownloadJob>>[
      vmtable.TableHeader(
        name: 'Model',
        childBuilder: _header,
        width: 280,
        minWidth: 180,
        sortKey: (j) => j.modelId,
        cellBuilder: (j) => _cell(j.modelId),
      ),
      vmtable.TableHeader(
        name: 'Quant',
        childBuilder: _header,
        width: 80,
        minWidth: 56,
        sortKey: (j) => j.quant,
        cellBuilder: (j) => _cell(j.quant),
      ),
      vmtable.TableHeader(
        name: 'Status',
        childBuilder: _header,
        width: 120,
        minWidth: 80,
        sortKey: (j) => j.status.name,
        cellBuilder: (j) {
          final label = switch (j.status) {
            ModelJobStatus.queued => l10n.modelsJobQueued,
            ModelJobStatus.running => l10n.modelsJobRunning,
            ModelJobStatus.done => l10n.modelsJobDone,
            ModelJobStatus.error => l10n.modelsJobError,
          };
          return _cell(j.status == ModelJobStatus.running
              ? '$label ${j.percent}%'
              : label);
        },
      ),
      vmtable.TableHeader(
        name: 'Detail',
        childBuilder: _header,
        width: 240,
        minWidth: 120,
        cellBuilder: (j) => _cell(j.error),
      ),
    ];

    return vmtable.Table<ModelDownloadJob>(
      headers: headers,
      data: jobs,
      rowExtent: 28,
      cellMargin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      finalRow: List.generate(headers.length, (_) => const SizedBox.shrink()),
    );
  }
}

bool isCachedModelGroupInUse(
  CachedModelGroup group,
  Iterable<LoadedModelInfo> loaded, {
  Iterable<PendingLlmLoad> pendingLoads = const [],
}) {
  return group.artifacts.any(
    (art) => isCachedModelInUse(art.model, loaded, pendingLoads: pendingLoads),
  );
}

Future<void> confirmDeleteCachedModel(
  BuildContext context,
  WidgetRef ref,
  CachedModelGroup group,
) async {
  final loaded = ref.read(loadedModelsProvider).asData?.value.models ??
      const <LoadedModelInfo>[];
  final pendingLoads = ref.read(pendingLlmLoadsProvider);
  if (isCachedModelGroupInUse(group, loaded, pendingLoads: pendingLoads)) {
    return;
  }

  final l10n = AppLocalizations.of(context)!;
  final body = group.hasMultiple
      ? l10n.modelsDeleteCachedMultiBody
      : l10n.modelsDeleteCachedBody;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ConfirmationDialog(
      title: l10n.modelsDeleteCachedTitle,
      body: Text(body),
      actionText: l10n.commonDelete,
      onAction: () async {
        Navigator.pop(context);
        await ref.read(grpcClientProvider).deleteModel(group.id);
        ref.invalidate(loadedModelsProvider);
      },
      inactionText: l10n.commonCancel,
      onInaction: () => Navigator.pop(context),
    ),
  );
}

class LlmCachedModelsGrid extends StatelessWidget {
  const LlmCachedModelsGrid({required this.models, super.key});

  final List<ModelSuggestion> models;

  @override
  Widget build(BuildContext context) {
    final groups = groupCachedModels(models);
    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const minCardWidth = 240.0;
          const spacing = 16.0;
          final nCards = max(1, constraints.maxWidth ~/ minCardWidth);
          final cardWidth =
              (constraints.maxWidth - spacing * (nCards - 1)) / nCards;

          final rows = <Widget>[];
          for (var i = 0; i < groups.length; i += nCards) {
            final rowGroups = groups.skip(i).take(nCards).toList();
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < rowGroups.length; j++) ...[
                      if (j > 0) const SizedBox(width: spacing),
                      LlmCachedModelCard(
                        group: rowGroups[j],
                        width: cardWidth,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return Column(
            children:
                rows.intersperse(const SizedBox(height: spacing)).toList(),
          );
        },
      ),
    );
  }
}

class LlmCachedModelCard extends ConsumerStatefulWidget {
  const LlmCachedModelCard({
    required this.group,
    required this.width,
    super.key,
  });

  final CachedModelGroup group;
  final double width;

  @override
  ConsumerState<LlmCachedModelCard> createState() => _LlmCachedModelCardState();
}

class _LlmCachedModelCardState extends ConsumerState<LlmCachedModelCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final group = widget.group;
    final model = group.primary;
    final loadSeed = group.loadSeed;
    final branding = brandingForSuggestion(model);
    final topPicks =
        ref.watch(topPicksModelsProvider).asData?.value ?? const [];
    final capabilities = capabilitiesForSuggestion(model, hints: topPicks);
    final loaded = ref.watch(loadedModelsProvider).asData?.value.models ??
        const <LoadedModelInfo>[];
    final pendingLoads = ref.watch(pendingLlmLoadsProvider);
    final inUse =
        isCachedModelGroupInUse(group, loaded, pendingLoads: pendingLoads);
    final loadPending = pendingLoads.any((load) => load.modelId == group.id);
    final brandMeta =
        branding.displayName.isNotEmpty ? branding.displayName : '';
    final artifactLines = group.artifacts.map((a) => a.summary).toList();
    final artifactTooltip = artifactLines.join('\n');
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.width,
        height: group.hasMultiple ? 248 : 220,
        child: CatalogueSurface(
          borderColor: _hovered ? Brand.primary.withValues(alpha: 0.45) : null,
          borderWidth: _hovered ? 1.5 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ModelProviderBadge(
                            branding: branding,
                            size: 40,
                            semanticsLabel: branding.displayName,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topRight,
                              child: ModelCapabilityChips(
                                capabilities: capabilities,
                                compact: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        group.title,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Tooltip(
                        message: artifactTooltip,
                        child: Text(
                          artifactLines.join('\n'),
                          style: TextStyle(
                            fontFamily: Brand.fontFamily,
                            fontSize: 11,
                            height: 1.35,
                            fontWeight: FontWeight.w400,
                            color: onSurface.withValues(alpha: 0.7),
                          ),
                          maxLines: group.hasMultiple ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      if (brandMeta.isNotEmpty)
                        Text(
                          brandMeta,
                          style: TextStyle(
                            fontFamily: Brand.fontFamily,
                            fontSize: 11,
                            color: onSurface.withValues(alpha: 0.55),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
              CardActionRow(
                actions: [
                  CardAction(
                    label: l10n.modelsLoad,
                    kind: LaunchPadButtonKind.primary,
                    onTap: loadPending
                        ? null
                        : () => loadLlmModel(
                              context,
                              ref,
                              modelId: loadSeed.id,
                              quant: loadSeed.bestQuant,
                              hfRepo: modelDownloadRepo(loadSeed),
                              format: CachedModelArtifact(loadSeed).format,
                              supportedRuntimes: loadSeed.supportedRuntimes,
                              suggestedCtx: suggestedCtxForModel(
                                usableContext: loadSeed.usableContext.toInt(),
                                contextLength: loadSeed.contextLength.toInt(),
                              ),
                            ),
                  ),
                  CardAction(
                    label: l10n.modelsOpenPath,
                    onTap: () => showCachedModelDetails(
                      context,
                      group,
                      hints: topPicks,
                    ),
                  ),
                  CardAction(
                    label: l10n.commonDelete,
                    kind: LaunchPadButtonKind.destructive,
                    onTap: inUse
                        ? null
                        : () => confirmDeleteCachedModel(context, ref, group),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}