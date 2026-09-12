import 'package:basics/basics.dart';
import 'package:built_collection/built_collection.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart' hide Table, Switch;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalogue/catalogue.dart';
import '../daemon_source.dart';
import '../dropdown.dart';
import '../l10n/app_localizations.dart';
import '../layout/compact_layout.dart';
import '../llm/host_resource_gauges.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../switch.dart';
import '../vm_details/memory_usage.dart';
import '../widgets/launchpad_button.dart';
import '../widgets/running_list_header.dart';
import 'bulk_actions.dart';
import 'header_selection.dart';
import 'search_box.dart';
import 'table.dart';
import 'vm_table_headers.dart';

class RunningOnlyNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void set(bool value) {
    state = value;
  }
}

final runningOnlyProvider = NotifierProvider<RunningOnlyNotifier, bool>(
  RunningOnlyNotifier.new,
);

class GroupByIntentNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    state = value;
  }
}

final groupByIntentProvider = NotifierProvider<GroupByIntentNotifier, bool>(
  GroupByIntentNotifier.new,
);

class SelectedIntentNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) {
    state = value;
  }
}

/// null means "all intents" (no filtering); the empty string filters down
/// to instances that aren't tagged with any intent at all.
final selectedIntentProvider = NotifierProvider<SelectedIntentNotifier, String?>(
  SelectedIntentNotifier.new,
);

final selectedVmsProvider =
    NotifierProvider<SelectedVmsNotifier, BuiltSet<VmId>>(
  SelectedVmsNotifier.new,
);

class SelectedVmsNotifier extends Notifier<BuiltSet<VmId>> {
  @override
  BuiltSet<VmId> build() {
    ref.watch(runningOnlyProvider);
    ref.watch(searchNameProvider);
    ref.watch(selectedIntentProvider);
    ref.watch(sidebarKeyProvider);
    ref.listen(vmIdsProvider, (_, availableIds) {
      state = availableIds.intersection(state);
    });

    return BuiltSet();
  }

  void set(BuiltSet<VmId> newState) {
    state = newState;
  }

  void toggle(VmId id, bool isSelected) {
    state = state.rebuild((set) {
      isSelected ? set.add(id) : set.remove(id);
    });
  }
}

class Vms extends ConsumerWidget {
  const Vms({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    goToCatalogue() {
      ref.read(sidebarKeyProvider.notifier).set(CatalogueScreen.sidebarKey);
    }

    final heading = RunningListHeader(
      title: l10n.vmTableAllInstances,
      subtitle: l10n.instancesSubtitle,
      action: LaunchPadButton.primary(
        onPressed: goToCatalogue,
        child: Text(l10n.commonLaunch),
      ),
    );

    final searchName = ref.watch(searchNameProvider);
    final runningOnly = ref.watch(runningOnlyProvider);
    final selectedIntent = ref.watch(selectedIntentProvider);
    final intentNames = ref.watch(intentNamesProvider);
    final intentFilter = intentNames.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Dropdown<String?>(
              label: 'Intent',
              width: 200,
              value: selectedIntent,
              onChanged: (v) => ref.read(selectedIntentProvider.notifier).set(v),
              items: {
                null: 'All intents',
                '': 'No intent',
                for (final intentName in intentNames) intentName: intentName,
              },
            ),
          );
    final groupByIntent = ref.watch(groupByIntentProvider);
    final vmFilters = Row(
      children: [
        Switch(
          label: l10n.vmTableShowRunningOnly,
          value: runningOnly,
          onChanged: (v) => ref.read(runningOnlyProvider.notifier).set(v),
        ),
        const SizedBox(width: 16),
        Switch(
          label: 'Group by intent',
          value: groupByIntent,
          onChanged: (v) => ref.read(groupByIntentProvider.notifier).set(v),
        ),
        const Spacer(),
        intentFilter,
        const SearchBox(),
        const SizedBox(width: 8),
        const HeaderSelection(),
      ],
    );

    final enabledHeaderNames = ref.watch(enabledHeadersProvider).asMap();
    final enabledHeaders =
        headers.where((h) => enabledHeaderNames[h.name]!).toList();
    final selectedVms = ref.watch(selectedVmsProvider);

    final infos = ref
        .watch(vmInfosProvider)
        .where((i) => !runningOnly || i.instanceStatus.status == Status.RUNNING)
        .where((i) => i.name.contains(searchName))
        .where((i) => selectedIntent == null || i.info.intent == selectedIntent)
        .toList();

    int total(Iterable<String> it) => it.map((e) => int.tryParse(e) ?? 0).sum;
    final totalUsedMemory = total(infos.map((i) => i.instanceInfo.memoryUsage));
    final totalTotalMemory = total(infos.map((i) => i.memoryTotal));
    final totalUsedDisk = total(infos.map((i) => i.instanceInfo.diskUsage));
    final totalTotalDisk = total(infos.map((i) => i.diskTotal));
    final totalUsageRow = [
      const SizedBox.shrink(),
      Container(
        margin: const EdgeInsets.all(10),
        alignment: Alignment.centerLeft,
        child: Text(
          l10n.vmTableTotal,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      for (final name in enabledHeaderNames.whereValue((e) => e).keys.skip(2))
        if (name == 'MEMORY USAGE')
          Container(
            margin: const EdgeInsets.all(10),
            child: MemoryUsage(
              used: '$totalUsedMemory',
              total: '$totalTotalMemory',
            ),
          )
        else if (name == 'DISK USAGE')
          Container(
            margin: const EdgeInsets.all(10),
            child: MemoryUsage(
              used: '$totalUsedDisk',
              total: '$totalTotalDisk',
            ),
          )
        else
          const SizedBox.shrink(),
    ];

    return Column(
      children: [
        heading,
        const SizedBox(height: 8),
        HostResourceGauges(compact: CompactScope.of(context)),
        const SizedBox(height: 16),
        vmFilters,
        const BulkActionsBar(),
        const SizedBox(height: 10),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: groupByIntent
                ? _GroupedByIntentTables(
                    infos: infos,
                    headers: enabledHeaders,
                    isSelected: (info) => selectedVms.contains(info.id),
                  )
                : Table<TaggedVmInfo>(
                    headers: enabledHeaders,
                    data: infos.toList(),
                    finalRow: totalUsageRow,
                    isSelected: (info) => selectedVms.contains(info.id),
                  ),
          ),
        ),
      ],
    );
  }
}

/// One [Table] per intent (plus one for untagged instances), stacked in a
/// scrollable column. Each table is given an explicit height sized to its
/// row count, since [Table] (a 2D scrollable) needs a bounded height and
/// can't just be dropped into an unbounded-height [ListView] like a normal
/// widget.
class _GroupedByIntentTables extends StatelessWidget {
  const _GroupedByIntentTables({
    required this.infos,
    required this.headers,
    required this.isSelected,
  });

  final List<TaggedVmInfo> infos;
  final List<TableHeader<TaggedVmInfo>> headers;
  final bool Function(TaggedVmInfo) isSelected;

  static const _headerRowHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<TaggedVmInfo>>{};
    for (final info in infos) {
      groups.putIfAbsent(info.info.intent, () => []).add(info);
    }
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty || b.isEmpty) return a.isEmpty ? 1 : -1;
        return a.compareTo(b);
      });

    if (sortedKeys.isEmpty) return const SizedBox.shrink();

    return ListView(
      children: [
        for (final key in sortedKeys) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              key.isEmpty ? 'No intent' : key,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            height: _headerRowHeight + groups[key]!.length * 50,
            child: Table<TaggedVmInfo>(
              headers: headers,
              data: groups[key]!,
              finalRow: const [],
              isSelected: isSelected,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
