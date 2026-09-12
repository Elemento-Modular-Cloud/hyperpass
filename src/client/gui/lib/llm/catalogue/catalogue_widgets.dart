import 'dart:math';

import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intersperse/intersperse.dart';

import '../../brand.dart';
import '../../catalogue/catalogue_surface.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../tooltip.dart';
import '../../vm_table/table.dart' as vmtable;
import '../../widgets/card_action_row.dart';
import '../../widgets/launchpad_button.dart';
import '../llm_features.dart';
import '../llm_load.dart';
import '../providers.dart';
import 'model_branding.dart';
import 'model_capabilities.dart';
import 'top_picks.dart';

class LlmCatalogFilters extends ConsumerWidget {
  final CatalogFilters filters;
  const LlmCatalogFilters({required this.filters, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final runtime =
        (!enableMlxBackend && filters.runtime == 'mlx') ? '' : filters.runtime;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(l10n.modelsFilterRuntime, style: const TextStyle(fontSize: 11)),
        ChoiceChip(
          label: Text(l10n.modelsFilterAny, style: const TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: runtime.isEmpty,
          onSelected: (_) =>
              ref.read(catalogFiltersProvider.notifier).setRuntime(''),
        ),
        ChoiceChip(
          label:
              Text(l10n.modelsRuntimeLlama, style: const TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: runtime == 'llamacpp',
          onSelected: (_) =>
              ref.read(catalogFiltersProvider.notifier).setRuntime('llamacpp'),
        ),
        if (enableMlxBackend)
          ChoiceChip(
            label:
                Text(l10n.modelsRuntimeMlx, style: const TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            selected: runtime == 'mlx',
            onSelected: (_) =>
                ref.read(catalogFiltersProvider.notifier).setRuntime('mlx'),
          ),
        const SizedBox(width: 6),
        Text(l10n.modelsFilterFit, style: const TextStyle(fontSize: 11)),
        ChoiceChip(
          label: Text(l10n.modelsFilterAny, style: const TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: filters.minFit.isEmpty,
          onSelected: (_) =>
              ref.read(catalogFiltersProvider.notifier).setMinFit(''),
        ),
        ChoiceChip(
          label:
              Text(l10n.modelsFitPerfect, style: const TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: filters.minFit == 'perfect',
          onSelected: (_) =>
              ref.read(catalogFiltersProvider.notifier).setMinFit('perfect'),
        ),
        ChoiceChip(
          label: Text(l10n.modelsFitGood, style: const TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: filters.minFit == 'good',
          onSelected: (_) =>
              ref.read(catalogFiltersProvider.notifier).setMinFit('good'),
        ),
        ChoiceChip(
          label:
              Text(l10n.modelsFitMarginal, style: const TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: filters.minFit == 'marginal',
          onSelected: (_) =>
              ref.read(catalogFiltersProvider.notifier).setMinFit('marginal'),
        ),
      ],
    );
  }
}

Color? llmFitColor(String fit, ColorScheme scheme) {
  final lower = fit.toLowerCase();
  if (lower.contains('perfect')) return Colors.green.shade400;
  if (lower.contains('good')) return Colors.lightGreen.shade400;
  if (lower.contains('marginal')) return Colors.orange.shade400;
  if (lower.contains('tight') || lower.contains('too')) return scheme.error;
  return null;
}

String llmModelParams(ModelSuggestion model) {
  if (model.parameterCount.isNotEmpty) return model.parameterCount;
  final match = RegExp(r'(\d+(?:\.\d+)?)[Bb](?:\b|[-_]|$)').firstMatch(model.id) ??
      RegExp(r'(\d+(?:\.\d+)?)[Bb](?:\b|[-_]|$)').firstMatch(model.name);
  return match != null ? '${match.group(1)}B' : '';
}

class LlmTopPicksGrid extends ConsumerWidget {
  const LlmTopPicksGrid({required this.models, super.key});

  final List<ModelSuggestion> models;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(catalogFiltersProvider.select((f) => f.search)).trim().toLowerCase();
    final filtered = query.isEmpty
        ? models
        : models
            .where((m) {
              final hay = [
                m.id,
                m.name,
                m.provider,
                m.category,
                m.useCase,
              ].join(' ').toLowerCase();
              return hay.contains(query);
            })
            .toList();

    if (filtered.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      return Center(
        child: Text(
          l10n.modelsCatalogEmpty,
          style: TextStyle(
            fontFamily: Brand.fontFamily,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const minCardWidth = 240.0;
          const spacing = 16.0;
          final nCards = max(1, constraints.maxWidth ~/ minCardWidth);
          final cardWidth =
              (constraints.maxWidth - spacing * (nCards - 1)) / nCards;

          final rows = <Widget>[];
          for (var i = 0; i < filtered.length; i += nCards) {
            final rowModels = filtered.skip(i).take(nCards).toList();
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < rowModels.length; j++) ...[
                      if (j > 0) const SizedBox(width: spacing),
                      LlmTopPickCard(model: rowModels[j], width: cardWidth),
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

class LlmTopPickCard extends ConsumerStatefulWidget {
  const LlmTopPickCard({
    required this.model,
    required this.width,
    super.key,
  });

  final ModelSuggestion model;
  final double width;

  @override
  ConsumerState<LlmTopPickCard> createState() => _LlmTopPickCardState();
}

class _LlmTopPickCardState extends ConsumerState<LlmTopPickCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final model = widget.model;
    final branding = brandingForSuggestion(model);
    final title = model.name.isEmpty ? model.id : model.name;
    final blurb = topPickBlurb(model);
    final params = llmModelParams(model);
    final capabilities = capabilitiesForSuggestion(model);
    final meta = [
      if (branding.displayName.isNotEmpty) branding.displayName,
      if (params.isNotEmpty) params,
      if (model.fitLevel.isNotEmpty) model.fitLevel,
      if (model.bestQuant.isNotEmpty) model.bestQuant,
    ].join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.width,
        height: 230,
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
                      Text(
                        blurb,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: 11,
                          height: 1.35,
                          fontWeight: FontWeight.w300,
                          color: onSurface.withValues(alpha: 0.7),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
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
                    label: l10n.modelsDownload,
                    kind: LaunchPadButtonKind.primary,
                    onTap: () => ref
                        .read(modelDownloadQueueProvider.notifier)
                        .enqueueDownload(
                          model.id,
                          model.bestQuant,
                          hfRepo: modelDownloadRepo(model),
                        ),
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

class LlmRecommendedChip extends ConsumerWidget {
  final ModelSuggestion model;
  const LlmRecommendedChip({required this.model, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = model.name.isEmpty ? model.id : model.name;
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      onPressed: () => loadLlmModel(
            context,
            ref,
            modelId: model.id,
            quant: model.bestQuant,
            hfRepo: modelDownloadRepo(model),
            suggestedCtx: suggestedCtxForModel(
              usableContext: model.usableContext.toInt(),
              contextLength: model.contextLength.toInt(),
            ),
          ),
    );
  }
}

class LlmCatalogTable extends ConsumerWidget {
  final List<ModelSuggestion> models;
  const LlmCatalogTable({required this.models, super.key});

  static Widget _header(String name) {
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(name,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  static Widget _cell(String text, {Color? color}) {
    return Text(
      text.isEmpty ? '-' : text,
      style: TextStyle(fontSize: 10, color: color),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  static String _disk(ModelSuggestion model) {
    if (model.diskSizeGb <= 0) return '';
    final gb = model.diskSizeGb;
    return gb >= 10 ? '${gb.toStringAsFixed(0)}G' : '${gb.toStringAsFixed(1)}G';
  }

  static String _ctx(ModelSuggestion model) {
    final tokens = model.usableContext.toInt() > 0
        ? model.usableContext.toInt()
        : model.contextLength.toInt();
    if (tokens <= 0) return '';
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(0)}k';
    return '$tokens';
  }

  static String _useCase(ModelSuggestion model) {
    if (model.category.isNotEmpty) return model.category;
    return model.useCase;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final headers = <vmtable.TableHeader<ModelSuggestion>>[
      vmtable.TableHeader(
        name: 'Model',
        childBuilder: _header,
        width: 380,
        minWidth: 280,
        sortKey: (m) => m.name.isEmpty ? m.id : m.name,
        cellBuilder: (m) {
          final label = m.name.isEmpty ? m.id : m.name;
          return Tooltip(message: label, child: _cell(label));
        },
      ),
      vmtable.TableHeader(
        name: 'Provider',
        childBuilder: _header,
        width: 100,
        minWidth: 72,
        sortKey: (m) => m.provider,
        cellBuilder: (m) => _cell(m.provider),
      ),
      vmtable.TableHeader(
        name: 'Params',
        childBuilder: _header,
        width: 64,
        minWidth: 48,
        sortKey: (m) => llmModelParams(m),
        cellBuilder: (m) => _cell(llmModelParams(m)),
      ),
      vmtable.TableHeader(
        name: 'Score',
        childBuilder: _header,
        width: 52,
        minWidth: 44,
        sortKey: (m) => m.score.toStringAsFixed(1).padLeft(8, '0'),
        cellBuilder: (m) =>
            _cell(m.score > 0 ? m.score.round().toString() : ''),
      ),
      vmtable.TableHeader(
        name: 'tok/s',
        childBuilder: _header,
        width: 52,
        minWidth: 44,
        sortKey: (m) => m.estimatedTps.toStringAsFixed(1).padLeft(8, '0'),
        cellBuilder: (m) =>
            _cell(m.estimatedTps > 0 ? m.estimatedTps.toStringAsFixed(1) : ''),
      ),
      vmtable.TableHeader(
        name: 'Quant',
        childBuilder: _header,
        width: 80,
        minWidth: 56,
        sortKey: (m) => m.bestQuant,
        cellBuilder: (m) => _cell(m.bestQuant),
      ),
      vmtable.TableHeader(
        name: 'Disk',
        childBuilder: _header,
        width: 52,
        minWidth: 44,
        sortKey: (m) => m.diskSizeGb.toStringAsFixed(2).padLeft(8, '0'),
        cellBuilder: (m) => _cell(_disk(m)),
      ),
      vmtable.TableHeader(
        name: 'Mode',
        childBuilder: _header,
        width: 52,
        minWidth: 44,
        sortKey: (m) => m.runMode,
        cellBuilder: (m) => _cell(m.runMode),
      ),
      vmtable.TableHeader(
        name: 'Mem %',
        childBuilder: _header,
        width: 56,
        minWidth: 48,
        sortKey: (m) => m.utilizationPct.toStringAsFixed(1).padLeft(8, '0'),
        cellBuilder: (m) =>
            _cell(m.utilizationPct > 0 ? '${m.utilizationPct.round()}%' : ''),
      ),
      vmtable.TableHeader(
        name: 'Ctx',
        childBuilder: _header,
        width: 56,
        minWidth: 44,
        sortKey: (m) => _ctx(m).padLeft(8, '0'),
        cellBuilder: (m) => _cell(_ctx(m)),
      ),
      vmtable.TableHeader(
        name: 'Date',
        childBuilder: _header,
        width: 64,
        minWidth: 52,
        sortKey: (m) => m.releaseDate,
        cellBuilder: (m) => _cell(m.releaseDate),
      ),
      vmtable.TableHeader(
        name: 'Fit',
        childBuilder: _header,
        width: 72,
        minWidth: 56,
        sortKey: (m) => m.fitLevel,
        cellBuilder: (m) =>
            _cell(m.fitLevel, color: llmFitColor(m.fitLevel, scheme)),
      ),
      vmtable.TableHeader(
        name: 'Use Case',
        childBuilder: _header,
        width: 160,
        minWidth: 100,
        sortKey: (m) => _useCase(m),
        cellBuilder: (m) {
          final tags = capabilitiesForSuggestion(m);
          if (tags.isEmpty) return _cell(_useCase(m));
          return ModelCapabilityChips(
            capabilities: tags,
            compact: true,
            maxTags: 3,
          );
        },
      ),
      vmtable.TableHeader(
        name: 'Actions',
        childBuilder: _header,
        width: 120,
        minWidth: 96,
        cellBuilder: (m) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CatalogAction(
              label: l10n.modelsDownload,
              color: Brand.primary,
              onTap: () =>
                  ref.read(modelDownloadQueueProvider.notifier).enqueueDownload(
                        m.id,
                        m.bestQuant,
                        hfRepo: modelDownloadRepo(m),
                      ),
            ),
            _CatalogAction(
              label: l10n.modelsLoad,
              color: scheme.onSurface.withValues(alpha: 0.75),
              onTap: () => loadLlmModel(
                    context,
                    ref,
                    modelId: m.id,
                    quant: m.bestQuant,
                    hfRepo: modelDownloadRepo(m),
                    suggestedCtx: suggestedCtxForModel(
                      usableContext: m.usableContext.toInt(),
                      contextLength: m.contextLength.toInt(),
                    ),
                  ),
            ),
          ],
        ),
      ),
    ];

    return vmtable.Table<ModelSuggestion>(
      headers: headers,
      data: models,
      rowExtent: 28,
      cellMargin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      finalRow: List.generate(headers.length, (_) => const SizedBox.shrink()),
    );
  }
}

class _CatalogAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CatalogAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, color: color, height: 1.0),
        ),
      ),
    );
  }
}
