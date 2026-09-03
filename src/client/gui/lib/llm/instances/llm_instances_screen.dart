import 'dart:math';

import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../page_surface.dart';
import '../../providers.dart';
import '../../sidebar.dart';
import '../catalogue/llm_catalogue_screen.dart';
import '../my_models_widgets.dart';
import '../providers.dart';
import 'llm_instance_headers.dart';
import '../../vm_table/table.dart' as vmtable;

class LlmInstancesScreen extends ConsumerStatefulWidget {
  static const sidebarKey = 'llm-instances';

  const LlmInstancesScreen({super.key});

  @override
  ConsumerState<LlmInstancesScreen> createState() => _LlmInstancesScreenState();
}

class _LlmInstancesScreenState extends ConsumerState<LlmInstancesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: ref.read(myModelsTabProvider),
    );
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        ref.read(myModelsTabProvider.notifier).set(_tabs.index);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tabIndex = ref.watch(myModelsTabProvider);
    if (_tabs.index != tabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabs.index != tabIndex) {
          _tabs.animateTo(tabIndex);
        }
      });
    }

    final activeDownloads = ref.watch(modelDownloadQueueProvider).where((j) =>
        j.status == ModelJobStatus.queued || j.status == ModelJobStatus.running).length;

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.llmInstancesLabel,
              style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabs: [
                Tab(text: l10n.modelsTabRunning),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.modelsTabDownloaded),
                      if (activeDownloads > 0) ...[
                        const SizedBox(width: 8),
                        Badge(label: Text('$activeDownloads')),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  _LlmRunningPane(),
                  _LlmDownloadedPane(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LlmRunningPane extends ConsumerWidget {
  const _LlmRunningPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(loadedModelsProvider);
    final pending = ref.watch(pendingLlmUnloadsProvider);

    return loaded.when(
      data: (reply) {
        final models = reply.models
            .where((m) => !pending.contains(m.instanceId))
            .toList(growable: false);
        if (models.isEmpty) {
          return const NoLlmInstances();
        }
        return vmtable.Table<LoadedModelInfo>(
          key: ValueKey(models.map((m) => m.instanceId).join(',')),
          headers: llmInstanceHeaders,
          data: models,
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

class _LlmDownloadedPane extends ConsumerWidget {
  const _LlmDownloadedPane();

  static const _rowExtent = 28.0;
  static const _maxJobRows = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final jobs = ref
        .watch(modelDownloadQueueProvider)
        .where((j) => j.status != ModelJobStatus.done)
        .toList(growable: false);
    final cached = ref.watch(loadedModelsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (jobs.isNotEmpty) ...[
          Text(l10n.modelsActiveDownloadsHeading, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          SizedBox(
            // The table scrolls internally, so it needs a bounded height.
            height: min(jobs.length + 2, _maxJobRows) * _rowExtent,
            child: LlmActiveDownloadsTable(jobs: jobs),
          ),
          const SizedBox(height: 24),
        ],
        Text(l10n.modelsCachedHeading, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        Expanded(
          child: cached.when(
            data: (reply) {
              if (reply.cached.isEmpty) {
                return Text(l10n.modelsCachedEmpty);
              }
              return LlmCachedModelsTable(models: reply.cached);
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
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
