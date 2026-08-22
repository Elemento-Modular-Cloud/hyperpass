import 'package:basics/basics.dart';
import 'package:flutter/material.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';

import '../confirmation_dialog.dart';
import '../copyable_text.dart';
import '../extensions.dart';
import '../ffi.dart';
import '../l10n/app_localizations.dart';
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

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.cacheLabel,
                    style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(cacheInfoProvider),
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
            Expanded(
              child: cacheAsync.when(
                skipLoadingOnRefresh: false,
                data: (reply) => _buildTable(context, ref, reply, l10n),
                error: (error, _) => _buildError(context, ref, error, l10n),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
              ),
            ),
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

  Widget _buildTable(
    BuildContext context,
    WidgetRef ref,
    CacheInfoReply reply,
    AppLocalizations l10n,
  ) {
    if (reply.images.isEmpty) {
      return Center(
        child: Text(
          l10n.cacheEmpty,
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.6),
          ),
        ),
      );
    }

    final headers = <TableHeader<CacheImageInfo>>[
      TableHeader(
        name: 'IMAGE',
        childBuilder: (_) => TableHeader.defaultHeaderBuilder(l10n.cacheStatImage),
        width: 280,
        minWidth: 160,
        sortKey: (image) {
          final release = image.release;
          return release.isNotBlank ? release : image.os;
        },
        cellBuilder: (image) {
          final release = image.release;
          return Row(
            children: [
              DistroLogo(image.os),
              const SizedBox(width: 8),
              Flexible(
                child: CopyableText(
                  release.isNotBlank ? release.nonBreaking : '-',
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
