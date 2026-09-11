import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../layout/compact_layout.dart';
import '../../page_surface.dart';
import '../../providers.dart';
import '../../sidebar.dart';
import '../../vm_table/search_box.dart';
import '../../vm_table/table.dart' as vmtable;
import '../../widgets/launchpad_button.dart';
import '../../widgets/running_list_header.dart';
import '../catalogue/llm_catalogue_screen.dart';
import '../host_resource_gauges.dart';
import '../providers.dart';
import 'llm_bulk_actions.dart';
import 'llm_downloaded_screen.dart';
import 'llm_instance_headers.dart';
import 'llm_selection.dart';

class LlmInstancesScreen extends ConsumerWidget {
  static const sidebarKey = 'llm-instances';

  const LlmInstancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final loaded = ref.watch(loadedModelsProvider);
    final pending = ref.watch(pendingLlmUnloadsProvider);
    final starting = ref.watch(pendingLlmLoadsProvider);
    final search = ref.watch(llmSearchProvider);
    final selected = ref.watch(selectedLlmInstancesProvider);

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RunningListHeader(
              title: l10n.llmInstancesLabel,
              subtitle: l10n.llmInstancesSubtitle,
              action: LaunchPadButton.primary(
                onPressed: () => ref
                    .read(sidebarKeyProvider.notifier)
                    .set(LlmDownloadedScreen.sidebarKey),
                child: Text(l10n.llmLoadAction),
              ),
            ),
            const SizedBox(height: 8),
            HostResourceGauges(compact: CompactScope.of(context)),
            const SizedBox(height: 16),
            Expanded(
              child: loaded.when(
                skipLoadingOnReload: true,
                data: (reply) => _LlmInstancesBody(
                  live: reply.models
                      .where((m) => !pending.contains(m.instanceId))
                      .toList(growable: false),
                  starting: starting,
                  search: search,
                  selected: selected,
                ),
                loading: () => starting.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _LlmInstancesBody(
                        live: const [],
                        starting: starting,
                        search: search,
                        selected: selected,
                      ),
                error: (e, _) => starting.isEmpty
                    ? Center(child: Text('$e'))
                    : _LlmInstancesBody(
                        live: const [],
                        starting: starting,
                        search: search,
                        selected: selected,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LlmInstancesBody extends StatelessWidget {
  const _LlmInstancesBody({
    required this.live,
    required this.starting,
    required this.search,
    required this.selected,
  });

  final List<LoadedModelInfo> live;
  final List<PendingLlmLoad> starting;
  final String search;
  final BuiltSet<String> selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (live.isEmpty && starting.isEmpty) {
      return const NoLlmInstances();
    }

    final models = [
      ...live,
      for (final load in starting) load.placeholder,
    ].where((m) {
      if (search.isEmpty) return true;
      final q = search.toLowerCase();
      return m.modelId.toLowerCase().contains(q) ||
          m.openaiId.toLowerCase().contains(q) ||
          m.backend.toLowerCase().contains(q);
    }).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Spacer(),
            SearchBox(
              key: const ValueKey('llm-search'),
              hint: l10n.searchBoxHintModels,
              provider: llmSearchProvider,
            ),
          ],
        ),
        const LlmBulkActionsBar(),
        const SizedBox(height: 10),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: vmtable.Table<LoadedModelInfo>(
              key: const ValueKey('llm-instances-table'),
              headers: llmInstanceHeaders,
              data: models,
              finalRow: List.generate(
                llmInstanceHeaders.length,
                (_) => const SizedBox.shrink(),
              ),
              isSelected: (m) => selected.contains(m.instanceId),
            ),
          ),
        ),
      ],
    );
  }
}

class NoLlmInstances extends ConsumerWidget {
  const NoLlmInstances({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l10n.llmInstancesEmpty, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          Text(l10n.llmInstancesEmptyHint),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: () => ref
                    .read(sidebarKeyProvider.notifier)
                    .set(LlmDownloadedScreen.sidebarKey),
                child: Text(l10n.llmDownloadedLabel),
              ),
              OutlinedButton(
                onPressed: () => ref
                    .read(sidebarKeyProvider.notifier)
                    .set(LlmCatalogueScreen.sidebarKey),
                child: Text(l10n.llmBrowseCatalogAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
