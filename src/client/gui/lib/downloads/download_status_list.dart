import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand.dart';
import '../glass_panel.dart';
import '../l10n/app_localizations.dart';
import 'download_manager.dart';

class DownloadStatusList extends ConsumerWidget {
  const DownloadStatusList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final jobs = ref
        .watch(downloadManagerProvider)
        .where((job) => job.isActive)
        .toList(growable: false);
    if (jobs.isEmpty) return const SizedBox.shrink();

    final textStyle = TextStyle(
      fontFamily: Brand.fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: onSurface,
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
      decorationThickness: 0,
    );

    return DefaultTextStyle(
      style: textStyle,
      child: IconTheme.merge(
        data: IconThemeData(color: onSurface, size: 16),
        child: GlassPanel(
          role: SurfaceRole.panel,
          borderRadius: BorderRadius.circular(Brand.radius),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.downloadsHeading,
                style: textStyle.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final job in jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DownloadJobRow(
                    job: job,
                    textStyle: textStyle,
                    muted: onSurface.withValues(alpha: 0.7),
                    onCancel: job.kind == DownloadKind.vmImage
                        ? () => ref
                            .read(downloadManagerProvider.notifier)
                            .cancel(job.id)
                        : null,
                    cancelTooltip: l10n.commonCancel,
                    queuedLabel: l10n.modelsJobQueued,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadJobRow extends StatelessWidget {
  const _DownloadJobRow({
    required this.job,
    required this.textStyle,
    required this.muted,
    required this.queuedLabel,
    required this.cancelTooltip,
    this.onCancel,
  });

  final DownloadJob job;
  final TextStyle textStyle;
  final Color muted;
  final String queuedLabel;
  final String cancelTooltip;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final queued = job.status == DownloadStatus.queued;
    return Row(
      children: [
        Icon(
          queued ? Icons.schedule : Icons.downloading,
          size: 14,
          color: Brand.accent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 4),
              if (queued)
                Text(
                  queuedLabel,
                  style: textStyle.copyWith(fontSize: 11, color: muted),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: job.percent / 100,
                    color: Brand.accent,
                    backgroundColor: muted.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
        ),
        if (!queued) ...[
          const SizedBox(width: 8),
          Text(
            '${job.percent}%',
            style: textStyle.copyWith(fontSize: 11, color: muted),
          ),
        ],
        if (onCancel != null)
          Material(
            color: Colors.transparent,
            child: IconButton(
              tooltip: cancelTooltip,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              iconSize: 16,
              onPressed: onCancel,
              icon: Icon(Icons.close, color: muted),
            ),
          ),
      ],
    );
  }
}
