import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../page_surface.dart';
import '../../providers.dart';
import '../../sidebar.dart';
import '../catalogue/llm_catalogue_screen.dart';
import '../providers.dart';
import 'llm_instance_headers.dart';
import '../../vm_table/table.dart' as vmtable;

class LlmInstancesScreen extends ConsumerWidget {
  static const sidebarKey = 'llm-instances';

  const LlmInstancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final loaded = ref.watch(loadedModelsProvider);
    final hasInstances = loaded.when(
      data: (reply) => reply.models.isNotEmpty,
      loading: () => false,
      error: (_, __) => false,
    );

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.llmInstancesLabel,
              style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: hasInstances
                  ? const _LlmInstancesTable()
                  : const NoLlmInstances(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LlmInstancesTable extends ConsumerWidget {
  const _LlmInstancesTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(loadedModelsProvider);

    return loaded.when(
      data: (reply) {
        return vmtable.Table<LoadedModelInfo>(
          headers: llmInstanceHeaders,
          data: reply.models,
          rowExtent: 36,
          cellMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          finalRow: List.generate(llmInstanceHeaders.length, (_) => const SizedBox.shrink()),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
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
          TextButton(
            onPressed: () =>
                ref.read(sidebarKeyProvider.notifier).set(LlmCatalogueScreen.sidebarKey),
            child: Text(l10n.llmCatalogueLabel),
          ),
        ],
      ),
    );
  }
}
