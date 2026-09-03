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

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.llmCatalogueLabel,
              style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 16),
            const Expanded(child: LlmCatalogPane()),
            const SizedBox(height: 12),
            const LlmBackendsStrip(),
          ],
        ),
      ),
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
    final filters = ref.watch(catalogFiltersProvider);
    final recommended = ref.watch(recommendedModelsProvider);
    final catalog = ref.watch(catalogModelsProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) {
            ref.read(catalogFiltersProvider.notifier).setSearch(value);
            ref.read(debouncedCatalogQueryProvider.notifier).set(value);
          },
          style: TextStyle(fontFamily: Brand.fontFamily, fontSize: 13, color: onSurface),
          decoration: InputDecoration(
            hintText: l10n.modelsSearchHint,
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        LlmCatalogFilters(filters: filters),
        const SizedBox(height: 8),
        recommended.when(
          data: (reply) {
            if (reply.models.isEmpty) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.modelsSuggestedHeading, style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 4),
                SizedBox(
                  height: 28,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: reply.models.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (context, index) =>
                        LlmRecommendedChip(model: reply.models[index]),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        Expanded(
          child: catalog.when(
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
          ),
        ),
      ],
    );
  }
}

class LlmBackendsStrip extends ConsumerWidget {
  const LlmBackendsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final backends = ref.watch(llmBackendsProvider);
    final scheme = Theme.of(context).colorScheme;

    return backends.when(
      data: (reply) {
        if (reply.backends.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(l10n.modelsTabBackends, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => ref.invalidate(llmBackendsProvider),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: Text(l10n.modelsBackendsRefresh, style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final backend in reply.backends)
                  Chip(
                    avatar: Icon(
                      backend.status == 'ready' ? Icons.check_circle : Icons.error_outline,
                      size: 14,
                      color: backend.status == 'ready' ? scheme.primary : scheme.error,
                    ),
                    label: Text(
                      backend.name.isEmpty ? backend.id : backend.name,
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
