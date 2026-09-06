import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brand.dart';
import '../../l10n/app_localizations.dart';
import '../../page_surface.dart';
import 'catalogue_widgets.dart';
import '../providers.dart';

class LlmCatalogueScreen extends ConsumerWidget {
  static const sidebarKey = 'llm-catalogue';

  const LlmCatalogueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final advanced = ref.watch(catalogAdvancedModeProvider);

    // Top picks: cards float on wallpaper (Images/Services style).
    // Advanced: solid page surface (no wallpaper bleed-through).
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final toggle = _CatalogModeToggle(advanced: advanced);
            final header = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.llmCatalogueLabel,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 37,
                    fontWeight: FontWeight.w300,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  advanced
                      ? l10n.modelsAdvancedSubtitle
                      : l10n.modelsTopPicksSubtitle,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                  ),
                ),
              ],
            );

            if (constraints.maxWidth >= 720) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: header),
                  const SizedBox(width: 16),
                  toggle,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: toggle),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const Expanded(child: LlmCatalogPane()),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: advanced
          ? PageSurface(
              baseColor: context.glass.cardSolid,
              child: content,
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
              child: content,
            ),
    );
  }
}

class _CatalogModeToggle extends ConsumerWidget {
  const _CatalogModeToggle({required this.advanced});

  final bool advanced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 6,
      children: [
        ChoiceChip(
          label: Text(
            l10n.modelsModeTopPicks,
            style: const TextStyle(fontSize: 12, fontFamily: Brand.fontFamily),
          ),
          selected: !advanced,
          visualDensity: VisualDensity.compact,
          onSelected: (_) =>
              ref.read(catalogAdvancedModeProvider.notifier).set(false),
        ),
        ChoiceChip(
          label: Text(
            l10n.modelsModeAdvanced,
            style: const TextStyle(fontSize: 12, fontFamily: Brand.fontFamily),
          ),
          selected: advanced,
          visualDensity: VisualDensity.compact,
          onSelected: (_) =>
              ref.read(catalogAdvancedModeProvider.notifier).set(true),
        ),
      ],
    );
  }
}

class LlmCatalogPane extends ConsumerStatefulWidget {
  const LlmCatalogPane({super.key});

  @override
  ConsumerState<LlmCatalogPane> createState() => _LlmCatalogPaneState();
}

class _LlmCatalogPaneState extends ConsumerState<LlmCatalogPane> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final advanced = ref.watch(catalogAdvancedModeProvider);
    final filters = ref.watch(catalogFiltersProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 280,
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                ref.read(catalogFiltersProvider.notifier).setSearch(value);
                if (advanced) {
                  ref.read(debouncedCatalogQueryProvider.notifier).set(value);
                }
              },
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 13,
                color: onSurface,
              ),
              decoration: InputDecoration(
                hintText: advanced
                    ? l10n.modelsSearchHint
                    : l10n.modelsTopPicksSearchHint,
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
        if (advanced) ...[
          const SizedBox(height: 8),
          LlmCatalogFilters(filters: filters),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: advanced ? _buildAdvanced(l10n) : _buildTopPicks(l10n),
        ),
      ],
    );
  }

  Widget _buildTopPicks(AppLocalizations l10n) {
    final topPicks = ref.watch(topPicksModelsProvider);
    return topPicks.when(
      data: (models) {
        if (models.isEmpty) {
          return Text(l10n.modelsSuggestedEmpty);
        }
        return LlmTopPicksGrid(models: models);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('$e'),
    );
  }

  Widget _buildAdvanced(AppLocalizations l10n) {
    final catalog = ref.watch(catalogModelsProvider);
    return catalog.when(
      data: (reply) {
        if (reply.replyMessage.isNotEmpty && reply.models.isEmpty) {
          return Text(reply.replyMessage);
        }
        if (reply.models.isEmpty) {
          return Text(l10n.modelsCatalogEmpty);
        }
        return LlmCatalogTable(models: reply.models);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('$e'),
    );
  }
}
