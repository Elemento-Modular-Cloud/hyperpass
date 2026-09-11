import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../sidebar.dart';
import '../../tooltip.dart';
import '../../vm_table/search_box.dart';
import '../../vm_table/table.dart';
import '../catalogue/model_branding.dart';
import '../catalogue/model_capabilities.dart';
import '../llm_id.dart';
import '../providers.dart';
import 'llm_selection.dart';

Widget Function(String) _l10nHeader(String Function(AppLocalizations) label) {
  return (_) => Builder(
        builder: (context) => TableHeader.defaultHeaderBuilder(
            label(AppLocalizations.of(context)!)),
      );
}

final llmInstanceHeaders = <TableHeader<LoadedModelInfo>>[
  TableHeader(
    name: 'checkbox',
    childBuilder: (_) => const SelectAllLlmCheckbox(),
    width: 50,
    minWidth: 50,
    cellBuilder: (m) => SelectLlmCheckbox(
      m.instanceId,
      key: ValueKey(m.instanceId),
    ),
  ),
  TableHeader(
    name: 'MODEL',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnModel),
    width: 280,
    minWidth: 180,
    sortKey: (m) => m.openaiId.isEmpty ? m.modelId : m.openaiId,
    cellBuilder: (m) => LlmModelLink(m),
  ),
  TableHeader(
    name: 'TAGS',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnTags),
    width: 180,
    minWidth: 120,
    cellBuilder: (m) => _LlmCapabilityCell(model: m),
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
    width: 110,
    minWidth: 80,
    sortKey: (m) => m.state,
    cellBuilder: (m) => _LlmStateCell(model: m),
  ),
  TableHeader(
    name: 'PORT',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnPort),
    width: 72,
    minWidth: 56,
    sortKey: (m) => m.port.toString().padLeft(6, '0'),
    cellBuilder: (m) => Text(m.port > 0 ? '${m.port}' : '—'),
  ),
  TableHeader(
    name: 'MEMORY',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnMemory),
    width: 100,
    minWidth: 72,
    sortKey: (m) => m.memoryClaimed.toString().padLeft(12, '0'),
    cellBuilder: (m) {
      if (isPendingLlmLoad(m) || m.memoryClaimed.toInt() <= 0) {
        return const Text('—');
      }
      final bytes = m.memoryClaimed.toInt();
      final gib = bytes / (1024 * 1024 * 1024);
      return Text(gib >= 1 ? '${gib.toStringAsFixed(1)} GiB' : '$bytes B');
    },
  ),
  TableHeader(
    name: 'CONTEXT',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnCtxSize),
    width: 96,
    minWidth: 72,
    sortKey: (m) => m.ctxSize.toString().padLeft(8, '0'),
    cellBuilder: (m) => Text(
      m.ctxSize > 0 ? '${m.ctxSize}' : (isPendingLlmLoad(m) ? '—' : '4096'),
    ),
  ),
  TableHeader(
    name: 'MAX TOKENS',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnMaxTokens),
    width: 96,
    minWidth: 72,
    sortKey: (m) => m.maxTokens.toString().padLeft(8, '0'),
    cellBuilder: (m) => Text(m.maxTokens > 0 ? '${m.maxTokens}' : '—'),
  ),
  TableHeader(
    name: 'ACTIVITY',
    childBuilder: _l10nHeader((l10n) => l10n.llmTableColumnActivity),
    width: 56,
    minWidth: 48,
    cellBuilder: (m) => LlmActivityLink(m),
  ),
];

class SelectAllLlmCheckbox extends ConsumerWidget {
  const SelectAllLlmCheckbox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedLlmInstancesProvider);
    final search = ref.watch(llmSearchProvider);
    final pending = ref.watch(pendingLlmUnloadsProvider);
    final ids = ref
            .watch(loadedModelsProvider)
            .asData
            ?.value
            .models
            .where((m) => !pending.contains(m.instanceId))
            .where((m) => !isPendingLlmLoad(m))
            .where((m) {
              if (search.isEmpty) return true;
              final q = search.toLowerCase();
              return m.modelId.toLowerCase().contains(q) ||
                  m.openaiId.toLowerCase().contains(q) ||
                  m.backend.toLowerCase().contains(q);
            })
            .map((m) => m.instanceId)
            .toList() ??
        const <String>[];
    final allSelected = ids.isNotEmpty && selected.containsAll(ids);

    return Center(
      child: Checkbox(
        tristate: true,
        value: selected.isEmpty ? false : (allSelected ? true : null),
        onChanged: (checked) {
          ref.read(selectedLlmInstancesProvider.notifier).set(
                checked ?? false ? ids.toBuiltSet() : BuiltSet(),
              );
        },
      ),
    );
  }
}

class SelectLlmCheckbox extends ConsumerWidget {
  const SelectLlmCheckbox(this.instanceId, {super.key});

  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (instanceId.startsWith(pendingLlmLoadIdPrefix)) {
      return const Center(child: Checkbox(value: false, onChanged: null));
    }
    final selected = ref.watch(
      selectedLlmInstancesProvider.select((s) => s.contains(instanceId)),
    );
    return Center(
      child: Checkbox(
        value: selected,
        onChanged: (checked) => ref
            .read(selectedLlmInstancesProvider.notifier)
            .toggle(instanceId, checked!),
      ),
    );
  }
}

class _LlmStateCell extends StatelessWidget {
  const _LlmStateCell({required this.model});

  final LoadedModelInfo model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (isPendingLlmLoad(model)) {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              l10n.llmStateStarting,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    final label = model.state == 'loaded' ? l10n.llmStateLoaded : model.state;
    return Text(label, overflow: TextOverflow.ellipsis);
  }
}

class _LlmCapabilityCell extends ConsumerWidget {
  const _LlmCapabilityCell({required this.model});

  final LoadedModelInfo model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached =
        ref.watch(loadedModelsProvider).asData?.value.cached ?? const [];
    final topPicks =
        ref.watch(topPicksModelsProvider).asData?.value ?? const [];
    final tags = capabilitiesForLoaded(
      model,
      hints: [...cached, ...topPicks],
    );
    if (tags.isEmpty) {
      return Text(
        '—',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      );
    }
    return ModelCapabilityChips(
      capabilities: tags,
      compact: true,
      maxTags: 3,
    );
  }
}

class LlmModelLink extends ConsumerWidget {
  final LoadedModelInfo model;

  const LlmModelLink(this.model, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id =
        LlmInstanceId(instanceId: model.instanceId, modelId: model.modelId);
    final label = model.openaiId.isEmpty
        ? model.modelId
        : '${model.modelId} (${model.openaiId})';
    final branding = brandingForLoaded(model);
    final pending = isPendingLlmLoad(model);

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: pending
            ? null
            : () => ref.read(sidebarKeyProvider.notifier).set(id.sidebarKey),
        child: Row(
          children: [
            ModelProviderBadge(
              branding: branding,
              size: 22,
              semanticsLabel: branding.displayName,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class LlmActivityLink extends ConsumerWidget {
  final LoadedModelInfo model;

  const LlmActivityLink(this.model, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isPendingLlmLoad(model)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final id =
        LlmInstanceId(instanceId: model.instanceId, modelId: model.modelId);

    return Tooltip(
      message: l10n.llmTableColumnActivity,
      child: IconButton(
        icon: const Icon(Icons.article_outlined, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: () =>
            ref.read(sidebarKeyProvider.notifier).set(id.sidebarKey),
      ),
    );
  }
}
