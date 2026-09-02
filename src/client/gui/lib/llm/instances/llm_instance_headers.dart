import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../sidebar.dart';
import '../../tooltip.dart';
import '../../vm_table/table.dart';
import '../llm_id.dart';
import '../providers.dart';

Widget Function(String) _l10nHeader(String Function(AppLocalizations) label) {
  return (_) => Builder(
        builder: (context) => TableHeader.defaultHeaderBuilder(
            label(AppLocalizations.of(context)!)),
      );
}

final llmInstanceHeaders = <TableHeader<LoadedModelInfo>>[
  TableHeader(
    name: 'MODEL',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnModel),
    width: 220,
    minWidth: 120,
    sortKey: (m) => m.openaiId.isEmpty ? m.modelId : m.openaiId,
    cellBuilder: (m) => LlmModelLink(m),
  ),
  TableHeader(
    name: 'BACKEND',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnBackend),
    width: 100,
    minWidth: 72,
    sortKey: (m) => m.backend,
    cellBuilder: (m) => Text(m.backend, overflow: TextOverflow.ellipsis),
  ),
  TableHeader(
    name: 'STATE',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnState),
    width: 90,
    minWidth: 64,
    sortKey: (m) => m.state,
    cellBuilder: (m) => Text(m.state, overflow: TextOverflow.ellipsis),
  ),
  TableHeader(
    name: 'PORT',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnPort),
    width: 72,
    minWidth: 56,
    sortKey: (m) => m.port.toString().padLeft(6, '0'),
    cellBuilder: (m) => Text('${m.port}'),
  ),
  TableHeader(
    name: 'MEMORY',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnMemory),
    width: 100,
    minWidth: 72,
    sortKey: (m) => m.memoryClaimed.toString().padLeft(12, '0'),
    cellBuilder: (m) {
      final bytes = m.memoryClaimed.toInt();
      final gib = bytes / (1024 * 1024 * 1024);
      return Text(gib >= 1 ? '${gib.toStringAsFixed(1)} GiB' : '$bytes B');
    },
  ),
  TableHeader(
    name: 'ACTIVITY',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnActivity),
    width: 56,
    minWidth: 48,
    cellBuilder: (m) => LlmActivityLink(m),
  ),
  TableHeader(
    name: 'ACTIONS',
    childBuilder: (_) => const SizedBox.shrink(),
    width: 80,
    minWidth: 64,
    cellBuilder: (m) => _LlmUnloadButton(model: m),
  ),
];

class LlmModelLink extends ConsumerWidget {
  final LoadedModelInfo model;

  const LlmModelLink(this.model, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = LlmInstanceId(instanceId: model.instanceId, modelId: model.modelId);
    final label = model.openaiId.isEmpty
        ? model.modelId
        : '${model.modelId} (${model.openaiId})';

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => ref.read(sidebarKeyProvider.notifier).set(id.sidebarKey),
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class LlmActivityLink extends ConsumerWidget {
  final LoadedModelInfo model;

  const LlmActivityLink(this.model, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final id = LlmInstanceId(instanceId: model.instanceId, modelId: model.modelId);

    return Tooltip(
      message: l10n.llmTableColumnActivity,
      child: IconButton(
        icon: const Icon(Icons.article_outlined, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: () => ref.read(sidebarKeyProvider.notifier).set(id.sidebarKey),
      ),
    );
  }
}

class _LlmUnloadButton extends ConsumerWidget {
  final LoadedModelInfo model;
  const _LlmUnloadButton({required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton(
      onPressed: () async {
        await ref.read(grpcClientProvider).unloadModel(model.instanceId);
        ref.invalidate(loadedModelsProvider);
      },
      child: Text(l10n.modelsUnload, style: const TextStyle(fontSize: 11)),
    );
  }
}
