import 'package:basics/basics.dart';
import 'package:built_collection/built_collection.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart' hide Table, Switch;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalogue/catalogue.dart';
import '../daemon_source.dart';
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

final selectedVmsProvider =
    NotifierProvider<SelectedVmsNotifier, BuiltSet<VmId>>(
  SelectedVmsNotifier.new,
);

class SelectedVmsNotifier extends Notifier<BuiltSet<VmId>> {
  @override
  BuiltSet<VmId> build() {
    ref.watch(runningOnlyProvider);
    ref.watch(searchNameProvider);
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
    final vmFilters = Row(
      children: [
        Switch(
          label: l10n.vmTableShowRunningOnly,
          value: runningOnly,
          onChanged: (v) => ref.read(runningOnlyProvider.notifier).set(v),
        ),
        const Spacer(),
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
            child: Table<TaggedVmInfo>(
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
