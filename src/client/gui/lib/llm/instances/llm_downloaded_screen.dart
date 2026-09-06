import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../page_surface.dart';
import '../../sidebar.dart';
import '../../widgets/running_list_header.dart';
import '../catalogue/llm_catalogue_screen.dart';
import '../my_models_widgets.dart';
import '../providers.dart';

class LlmDownloadedScreen extends ConsumerWidget {
  static const sidebarKey = 'llm-downloaded';

  const LlmDownloadedScreen({super.key});

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

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RunningListHeader(
              title: l10n.llmDownloadedLabel,
              subtitle: l10n.llmDownloadedSubtitle,
              action: TextButton(
                onPressed: () => ref
                    .read(sidebarKeyProvider.notifier)
                    .set(LlmCatalogueScreen.sidebarKey),
                child: Text(l10n.llmBrowseCatalogAction),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (jobs.isNotEmpty) ...[
                    Text(
                      l10n.modelsActiveDownloadsHeading,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: min(jobs.length + 2, _maxJobRows) * _rowExtent,
                      child: LlmActiveDownloadsTable(jobs: jobs),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    l10n.modelsCachedHeading,
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: cached.when(
                      data: (reply) {
                        if (reply.cached.isEmpty && jobs.isEmpty) {
                          return const _EmptyDownloaded();
                        }
                        if (reply.cached.isEmpty) {
                          return Text(l10n.modelsCachedEmpty);
                        }
                        return LlmCachedModelsGrid(models: reply.cached);
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('$e'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDownloaded extends ConsumerWidget {
  const _EmptyDownloaded();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l10n.llmDownloadedEmpty, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          Text(l10n.llmDownloadedEmptyHint),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref
                .read(sidebarKeyProvider.notifier)
                .set(LlmCatalogueScreen.sidebarKey),
            child: Text(l10n.llmBrowseCatalogAction),
          ),
        ],
      ),
    );
  }
}
