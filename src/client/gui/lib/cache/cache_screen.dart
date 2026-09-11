import 'package:basics/basics.dart';
import 'package:flutter/material.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';

import '../auth/feature_access.dart';
import '../confirmation_dialog.dart';
import '../copyable_text.dart';
import '../distro_branding.dart';
import '../extensions.dart';
import '../ffi.dart';
import '../l10n/app_localizations.dart';
import '../llm/catalogue/model_branding.dart';
import '../llm/my_models_widgets.dart';
import '../llm/providers.dart';
import '../page_surface.dart';
import '../providers.dart';
import '../vm_table/table.dart';
import '../vm_table/vm_table_headers.dart';

final cacheInfoProvider = FutureProvider((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return CacheInfoReply();
  }
  return ref.watch(grpcClientProvider).cacheInfo();
});

class CacheScreen extends ConsumerWidget {
  static const sidebarKey = 'cache';

  const CacheScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cacheAsync = ref.watch(cacheInfoProvider);
    final showModels = ref.watch(featureAccessProvider).canUseLlms;

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.sidebarStorageLabel,
                    style: const TextStyle(
                      fontSize: 37,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.invalidate(cacheInfoProvider);
                    ref.invalidate(loadedModelsProvider);
                  },
                  child: Text(l10n.cacheRefresh),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    await ref
                        .read(grpcClientProvider)
                        .cacheDelete(pruneExpired: true);
                    ref.invalidate(cacheInfoProvider);
                  },
                  child: Text(l10n.cachePruneExpired),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: cacheAsync.maybeWhen(
                    data: (reply) => reply.images.isEmpty
                        ? null
                        : () => _confirmDeleteAll(context, ref, reply, l10n),
                    orElse: () => null,
                  ),
                  child: Text(l10n.cacheDeleteAll),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              l10n.cacheImagesHeading,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: showModels ? 3 : 1,
              child: cacheAsync.when(
                skipLoadingOnRefresh: false,
                data: (reply) => _buildImageTable(context, ref, reply, l10n),
                error: (error, _) => _buildError(context, ref, error, l10n),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
              ),
            ),
            if (showModels) ...[
              const SizedBox(height: 24),
              Text(
                l10n.cacheModelsHeading,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 2,
                child: _ModelsTable(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAll(
    BuildContext context,
    WidgetRef ref,
    CacheInfoReply reply,
    AppLocalizations l10n,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmationDialog(
        title: l10n.cacheDeleteAllTitle,
        body: Text(l10n.cacheDeleteAllBody),
        actionText: l10n.commonDelete,
        onAction: () async {
          Navigator.pop(context);
          await ref.read(grpcClientProvider).cacheDelete(
                ids: reply.images.map((image) => image.id),
              );
          ref.invalidate(cacheInfoProvider);
        },
        inactionText: l10n.commonCancel,
        onInaction: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildError(
    BuildContext context,
    WidgetRef ref,
    Object error,
    AppLocalizations l10n,
  ) {
    final message =
        error is GrpcError ? (error.message ?? error.toString()) : error.toString();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.cacheLoadError(message),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.invalidate(cacheInfoProvider),
            child: Text(l10n.cacheRefresh),
          ),
        ],
      ),
    );
  }

  Widget _buildImageTable(
    BuildContext context,
    WidgetRef ref,
    CacheInfoReply reply,
    AppLocalizations l10n,
  ) {
    if (reply.images.isEmpty) {
      return _EmptyHint(l10n.cacheEmpty);
    }

    final headers = <TableHeader<CacheImageInfo>>[
      TableHeader(
        name: 'IMAGE',
        childBuilder: (_) => TableHeader.defaultHeaderBuilder(l10n.cacheStatImage),
        width: 280,
        minWidth: 160,
        sortKey: (image) => _cacheImageLabel(image),
        cellBuilder: (image) {
          final label = _cacheImageLabel(image);
          return Row(
            children: [
              DistroLogo(
                image.os,
                release: image.release,
                aliases: image.aliases,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: CopyableText(
                  label.isNotBlank ? label.nonBreaking : '-',
                ),
              ),
            ],
          );
        },
      ),
      TableHeader(
        name: 'SIZE',
        childBuilder: (_) => TableHeader.defaultHeaderBuilder(l10n.cacheStatSize),
        width: 160,
        minWidth: 100,
        sortKey: (image) => image.sizeBytes.toString().padLeft(20, '0'),
        cellBuilder: (image) => Text(
          humanReadableMemory(image.sizeBytes.toInt()),
        ),
      ),
      TableHeader(
        name: 'ACTIONS',
        childBuilder: (_) => TableHeader.defaultHeaderBuilder(l10n.cacheStatActions),
        width: 72,
        minWidth: 56,
        cellBuilder: (image) => Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: l10n.cacheDeleteTooltip,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await ref.read(grpcClientProvider).cacheDelete(ids: [image.id]);
              ref.invalidate(cacheInfoProvider);
            },
          ),
        ),
      ),
    ];

    final totalRow = [
      Container(
        margin: const EdgeInsets.all(10),
        alignment: Alignment.centerLeft,
        child: Text(
          l10n.cacheTableTotal,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      Container(
        margin: const EdgeInsets.all(10),
        alignment: Alignment.centerLeft,
        child: Text(
          humanReadableMemory(reply.totalBytes.toInt()),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      const SizedBox.shrink(),
    ];

    return Table(
      headers: headers,
      data: reply.images,
      finalRow: totalRow,
    );
  }
}

class _ModelsTable extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final modelsAsync = ref.watch(loadedModelsProvider);

    return modelsAsync.when(
      data: (reply) {
        final models = reply.cached;
        if (models.isEmpty) {
          return _EmptyHint(l10n.cacheModelsEmpty);
        }

        final loaded = reply.models;
        final pendingLoads = ref.watch(pendingLlmLoadsProvider);
        var totalBytes = 0;
        for (final model in models) {
          totalBytes += cachedModelDiskBytes(model);
        }

        final headers = <TableHeader<ModelSuggestion>>[
          TableHeader(
            name: 'MODEL',
            childBuilder: (_) =>
                TableHeader.defaultHeaderBuilder(l10n.cacheModelsStatName),
            width: 280,
            minWidth: 160,
            sortKey: (model) => model.name.isNotEmpty ? model.name : model.id,
            cellBuilder: (model) {
              final title = model.name.isEmpty ? model.id : model.name;
              final branding = brandingForSuggestion(model);
              return Row(
                children: [
                  ModelProviderBadge(
                    branding: branding,
                    size: 28,
                    semanticsLabel: branding.displayName,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: CopyableText(
                      title.isNotBlank ? title.nonBreaking : '-',
                    ),
                  ),
                ],
              );
            },
          ),
          TableHeader(
            name: 'SIZE',
            childBuilder: (_) =>
                TableHeader.defaultHeaderBuilder(l10n.cacheStatSize),
            width: 140,
            minWidth: 100,
            sortKey: (model) =>
                cachedModelDiskBytes(model).toString().padLeft(20, '0'),
            cellBuilder: (model) {
              final bytes = cachedModelDiskBytes(model);
              return Text(bytes > 0 ? humanReadableMemory(bytes) : '-');
            },
          ),
          TableHeader(
            name: 'STATUS',
            childBuilder: (_) =>
                TableHeader.defaultHeaderBuilder(l10n.cacheModelsStatStatus),
            width: 120,
            minWidth: 88,
            sortKey: (model) =>
                isCachedModelInUse(model, loaded, pendingLoads: pendingLoads)
                    ? '1'
                    : '0',
            cellBuilder: (model) => Text(
              isCachedModelInUse(model, loaded, pendingLoads: pendingLoads)
                  ? l10n.cacheModelsInUse
                  : l10n.cacheModelsAvailable,
            ),
          ),
          TableHeader(
            name: 'ACTIONS',
            childBuilder: (_) =>
                TableHeader.defaultHeaderBuilder(l10n.cacheStatActions),
            width: 72,
            minWidth: 56,
            cellBuilder: (model) {
              final inUse =
                  isCachedModelInUse(model, loaded, pendingLoads: pendingLoads);
              return Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: inUse
                      ? l10n.cacheDeleteModelInUseTooltip
                      : l10n.modelsDeleteCachedTooltip,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: inUse
                      ? null
                      : () => confirmDeleteCachedModel(context, ref, model),
                ),
              );
            },
          ),
        ];

        final totalRow = [
          Container(
            margin: const EdgeInsets.all(10),
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.cacheTableTotal,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Container(
            margin: const EdgeInsets.all(10),
            alignment: Alignment.centerLeft,
            child: Text(
              totalBytes > 0 ? humanReadableMemory(totalBytes) : '-',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox.shrink(),
          const SizedBox.shrink(),
        ];

        return Table(
          headers: headers,
          data: models,
          finalRow: totalRow,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _EmptyHint('$error'),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// Prefer "Ubuntu 24.04 LTS" / "Alpine Linux 3.24.1" over bare version strings.
String _cacheImageLabel(CacheImageInfo image) {
  final os = image.os.trim();
  final release = image.release.trim();
  final family = distroDisplayName(os, release: release);

  if (release.isEmpty) return family == '-' ? os : family;
  if (family == '-' || family.isEmpty) return release;

  final releaseLower = release.toLowerCase();
  final familyToken = family.toLowerCase().split(RegExp(r'\s+')).first;
  if (releaseLower.contains(familyToken)) return release;

  return '$family $release';
}
