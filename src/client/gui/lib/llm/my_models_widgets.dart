import 'dart:io';

import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../confirmation_dialog.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../tooltip.dart';
import '../vm_table/table.dart' as vmtable;
import 'llm_load.dart';
import 'providers.dart';

Future<void> revealModelPath(String path) async {
  if (path.isEmpty) return;
  final file = File(path);
  if (Platform.isMacOS) {
    if (await file.exists()) {
      await Process.run('open', ['-R', path]);
    } else {
      await Process.run('open', [File(path).parent.path]);
    }
    return;
  }
  if (Platform.isLinux) {
    await Process.run('xdg-open', [file.parent.path]);
    return;
  }
  if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', path]);
  }
}

class LlmActiveDownloadsTable extends ConsumerWidget {
  final List<ModelDownloadJob> jobs;

  const LlmActiveDownloadsTable({required this.jobs, super.key});

  static Widget _header(String name) {
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  static Widget _cell(String text) {
    return Text(
      text.isEmpty ? '-' : text,
      style: const TextStyle(fontSize: 10),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final headers = <vmtable.TableHeader<ModelDownloadJob>>[
      vmtable.TableHeader(
        name: 'Model',
        childBuilder: _header,
        width: 280,
        minWidth: 180,
        sortKey: (j) => j.modelId,
        cellBuilder: (j) => _cell(j.modelId),
      ),
      vmtable.TableHeader(
        name: 'Quant',
        childBuilder: _header,
        width: 80,
        minWidth: 56,
        sortKey: (j) => j.quant,
        cellBuilder: (j) => _cell(j.quant),
      ),
      vmtable.TableHeader(
        name: 'Status',
        childBuilder: _header,
        width: 120,
        minWidth: 80,
        sortKey: (j) => j.status.name,
        cellBuilder: (j) {
          final label = switch (j.status) {
            ModelJobStatus.queued => l10n.modelsJobQueued,
            ModelJobStatus.running => l10n.modelsJobRunning,
            ModelJobStatus.done => l10n.modelsJobDone,
            ModelJobStatus.error => l10n.modelsJobError,
          };
          return _cell(j.status == ModelJobStatus.running ? '$label ${j.percent}%' : label);
        },
      ),
      vmtable.TableHeader(
        name: 'Detail',
        childBuilder: _header,
        width: 240,
        minWidth: 120,
        cellBuilder: (j) => _cell(j.error),
      ),
    ];

    return vmtable.Table<ModelDownloadJob>(
      headers: headers,
      data: jobs,
      rowExtent: 28,
      cellMargin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      finalRow: List.generate(headers.length, (_) => const SizedBox.shrink()),
    );
  }
}

class LlmCachedModelsTable extends ConsumerWidget {
  final List<ModelSuggestion> models;

  const LlmCachedModelsTable({required this.models, super.key});

  static Widget _header(String name) {
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  static Widget _cell(String text) {
    return Text(
      text.isEmpty ? '-' : text,
      style: const TextStyle(fontSize: 10),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, ModelSuggestion model) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmationDialog(
        title: l10n.modelsDeleteCachedTitle,
        body: Text(l10n.modelsDeleteCachedBody),
        actionText: l10n.commonDelete,
        onAction: () async {
          Navigator.pop(context);
          await ref.read(grpcClientProvider).deleteModel(model.id);
          ref.invalidate(loadedModelsProvider);
        },
        inactionText: l10n.commonCancel,
        onInaction: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final headers = <vmtable.TableHeader<ModelSuggestion>>[
      vmtable.TableHeader(
        name: 'Model',
        childBuilder: _header,
        width: 280,
        minWidth: 180,
        sortKey: (m) => m.name.isEmpty ? m.id : m.name,
        cellBuilder: (m) {
          final label = m.name.isEmpty ? m.id : m.name;
          return Tooltip(message: label, child: _cell(label));
        },
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
        name: 'Size',
        childBuilder: _header,
        width: 72,
        minWidth: 56,
        sortKey: (m) => m.memoryRequiredGb.toStringAsFixed(2).padLeft(8, '0'),
        cellBuilder: (m) => _cell(
          m.memoryRequiredGb > 0 ? '${m.memoryRequiredGb.toStringAsFixed(1)} GiB' : '',
        ),
      ),
      vmtable.TableHeader(
        name: 'Path',
        childBuilder: _header,
        width: 220,
        minWidth: 120,
        sortKey: (m) => m.path,
        cellBuilder: (m) => Tooltip(message: m.path, child: _cell(m.path)),
      ),
      vmtable.TableHeader(
        name: 'Actions',
        childBuilder: _header,
        width: 180,
        minWidth: 140,
        cellBuilder: (m) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TableAction(
              label: l10n.modelsLoad,
              color: scheme.primary,
              onTap: () => loadLlmModel(
                context,
                ref,
                modelId: m.id,
                quant: m.bestQuant,
                hfRepo: modelDownloadRepo(m),
              ),
            ),
            if (m.path.isNotEmpty)
              _TableAction(
                label: l10n.modelsOpenPath,
                color: scheme.primary,
                onTap: () => revealModelPath(m.path),
              ),
            _TableAction(
              label: l10n.commonDelete,
              color: scheme.error,
              onTap: () => _confirmDelete(context, ref, m),
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

class _TableAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TableAction({
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
        child: Text(label, style: TextStyle(fontSize: 10, color: color, height: 1.0)),
      ),
    );
  }
}
