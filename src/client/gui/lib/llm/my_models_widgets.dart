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

Future<void> showCachedModelDetails(
  BuildContext context,
  ModelSuggestion model, {
  Iterable<ModelSuggestion> hints = const [],
}) async {
  final l10n = AppLocalizations.of(context)!;
  final title = model.name.isEmpty ? model.id : model.name;
  final rows = <(String, String)>[
    if (model.id.isNotEmpty) (l10n.modelsDetailId, model.id),
    if (model.provider.isNotEmpty) (l10n.modelsDetailProvider, model.provider),
    if (model.bestQuant.isNotEmpty) (l10n.modelsDetailQuant, model.bestQuant),
    if (model.filename.isNotEmpty) (l10n.modelsDetailFilename, model.filename),
    if (model.hfRepo.isNotEmpty) (l10n.modelsDetailHfRepo, model.hfRepo),
    if (model.parameterCount.isNotEmpty)
      (l10n.modelsDetailParams, model.parameterCount),
    if (model.memoryRequiredGb > 0)
      (
        l10n.modelsDetailMemory,
        '${model.memoryRequiredGb.toStringAsFixed(1)} GiB'
      ),
    if (model.diskSizeGb > 0)
      (l10n.modelsDetailDisk, '${model.diskSizeGb.toStringAsFixed(1)} GiB'),
    if (model.path.isNotEmpty) (l10n.modelsDetailPath, model.path),
  ];
  final capabilities = capabilitiesForSuggestion(model, hints: hints);

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
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
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(name,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    );
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

Future<void> confirmDeleteCachedModel(
  BuildContext context,
  WidgetRef ref,
  ModelSuggestion model,
) async {
  final loaded = ref.read(loadedModelsProvider).asData?.value.models ??
      const <LoadedModelInfo>[];
  final pendingLoads = ref.read(pendingLlmLoadsProvider);
  if (isCachedModelInUse(model, loaded, pendingLoads: pendingLoads)) return;

  final l10n = AppLocalizations.of(context)!;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ConfirmationDialog(
      title: l10n.modelsDeleteCachedTitle,
      body: Text(l10n.modelsDeleteCachedBody),
      actionText: l10n.commonDelete,
      onAction: () async {
        Navigator.pop(context);
        await ref.read(grpcClientProvider).deleteModel(model.id);
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
    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const minCardWidth = 240.0;
          const spacing = 16.0;
          final nCards = max(1, constraints.maxWidth ~/ minCardWidth);
          final cardWidth =
              (constraints.maxWidth - spacing * (nCards - 1)) / nCards;

          final rows = <Widget>[];
          for (var i = 0; i < models.length; i += nCards) {
            final rowModels = models.skip(i).take(nCards).toList();
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < rowModels.length; j++) ...[
                      if (j > 0) const SizedBox(width: spacing),
                      LlmCachedModelCard(model: rowModels[j], width: cardWidth),
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
    required this.model,
    required this.width,
    super.key,
  });

  final ModelSuggestion model;
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
    final model = widget.model;
    final branding = brandingForSuggestion(model);
    final title = model.name.isEmpty ? model.id : model.name;
    final quant = model.bestQuant;
    final topPicks =
        ref.watch(topPicksModelsProvider).asData?.value ?? const [];
    final capabilities = capabilitiesForSuggestion(model, hints: topPicks);
    final loaded = ref.watch(loadedModelsProvider).asData?.value.models ??
        const <LoadedModelInfo>[];
    final pendingLoads = ref.watch(pendingLlmLoadsProvider);
    final inUse =
        isCachedModelInUse(model, loaded, pendingLoads: pendingLoads);
    final loadPending = pendingLoads.any((load) => load.modelId == model.id);
    final sizeLabel = model.memoryRequiredGb > 0
        ? '${model.memoryRequiredGb.toStringAsFixed(1)} GiB'
        : (model.diskSizeGb > 0
            ? '${model.diskSizeGb.toStringAsFixed(1)} GiB'
            : '');
    final meta = [
      if (branding.displayName.isNotEmpty) branding.displayName,
      if (quant.isNotEmpty) quant,
      if (sizeLabel.isNotEmpty) sizeLabel,
    ].join(' · ');
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.width,
        height: 220,
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
                        title,
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
                      if (model.path.isNotEmpty)
                        Tooltip(
                          message: model.path,
                          child: Text(
                            model.path,
                            style: TextStyle(
                              fontFamily: Brand.fontFamily,
                              fontSize: 11,
                              height: 1.35,
                              fontWeight: FontWeight.w300,
                              color: onSurface.withValues(alpha: 0.7),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const Spacer(),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
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
                              modelId: model.id,
                              quant: model.bestQuant,
                              hfRepo: modelDownloadRepo(model),
                            ),
                  ),
                  CardAction(
                    label: l10n.modelsOpenPath,
                    onTap: () =>
                        showCachedModelDetails(context, model, hints: topPicks),
                  ),
                  CardAction(
                    label: l10n.commonDelete,
                    kind: LaunchPadButtonKind.destructive,
                    onTap: inUse
                        ? null
                        : () => confirmDeleteCachedModel(context, ref, model),
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