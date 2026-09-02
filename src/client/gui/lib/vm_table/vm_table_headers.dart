import 'package:basics/basics.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../copyable_text.dart';
import '../daemon_source.dart';
import '../distro_branding.dart';
import '../extensions.dart';
import '../l10n/app_localizations.dart';
import '../multipass_chip.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../tooltip.dart';
import '../vm_details/cpu_sparkline.dart';
import '../vm_details/ip_addresses.dart';
import '../vm_details/memory_usage.dart';
import '../vm_details/vm_details.dart';
import '../vm_details/vm_status_icon.dart';
import 'search_box.dart';
import 'table.dart';
import 'vms.dart';

/// Returns a [childBuilder] for [TableHeader] that renders a localized column label.
Widget Function(String) _l10nHeader(String Function(AppLocalizations) label) {
  return (_) => Builder(
        builder: (context) => TableHeader.defaultHeaderBuilder(
            label(AppLocalizations.of(context)!)),
      );
}

final headers = <TableHeader<TaggedVmInfo>>[
  TableHeader(
    name: 'checkbox',
    childBuilder: (_) => const SelectAllCheckbox(),
    width: 50,
    minWidth: 50,
    cellBuilder: (info) => SelectVmCheckbox(info.id),
  ),
  TableHeader(
    name: 'NAME',
    childBuilder: _l10nHeader((l10n) => l10n.vmTableColumnName),
    width: 150,
    minWidth: 90,
    sortKey: (info) => info.name,
    cellBuilder: (info) => VmNameLink(info.id),
  ),
  TableHeader(
    name: 'SHELL',
    childBuilder: _l10nHeader((l10n) => l10n.vmTableColumnShell),
    width: 56,
    minWidth: 48,
    cellBuilder: (info) => VmShellLink(info.id),
  ),
  TableHeader(
    name: 'STATE',
    childBuilder: _l10nHeader((l10n) => l10n.vmStatState),
    width: 110,
    minWidth: 70,
    sortKey: (info) => info.instanceStatus.status.name,
    cellBuilder: (info) => Consumer(
      builder: (_, ref, __) => VmStatusIcon(
        info.instanceStatus.status,
        isLaunching: ref.watch(isLaunchingProvider(info.id)),
      ),
    ),
  ),
  TableHeader(
    name: 'CPU USAGE',
    childBuilder: _l10nHeader((l10n) => l10n.vmStatCpuUsage),
    width: 130,
    minWidth: 100,
    cellBuilder: (info) => CpuSparkline(info.id),
  ),
  TableHeader(
    name: 'MEMORY USAGE',
    childBuilder: _l10nHeader((l10n) => l10n.vmStatMemoryUsage),
    width: 140,
    minWidth: 130,
    cellBuilder: (info) => MemoryUsage(
      used: info.instanceInfo.memoryUsage,
      total: info.memoryTotal,
    ),
  ),
  TableHeader(
    name: 'DISK USAGE',
    childBuilder: _l10nHeader((l10n) => l10n.vmStatDiskUsage),
    width: 130,
    minWidth: 100,
    cellBuilder: (info) =>
        MemoryUsage(used: info.instanceInfo.diskUsage, total: info.diskTotal),
  ),
  TableHeader(
    name: 'IMAGE',
    childBuilder: _l10nHeader((l10n) => l10n.vmStatImage),
    width: 160,
    minWidth: 100,
    sortKey: (info) {
      final image = info.instanceInfo.currentRelease;
      return image.isNotBlank ? image : info.instanceInfo.os;
    },
    cellBuilder: (info) {
      final image = info.instanceInfo.currentRelease;
      return Row(
        children: [
          DistroLogo(
            info.instanceInfo.os,
            release: image,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: CopyableText(
              image.isNotBlank ? image.nonBreaking : '-',
            ),
          ),
        ],
      );
    },
  ),
  TableHeader(
    name: 'PRIVATE IP',
    childBuilder: _l10nHeader((l10n) => l10n.vmStatPrivateIp),
    width: 140,
    minWidth: 100,
    cellBuilder: (info) => IpAddresses(info.instanceInfo.ipv4.take(1)),
  ),
  TableHeader(
    name: 'PUBLIC IP',
    childBuilder: _l10nHeader((l10n) => l10n.vmStatPublicIp),
    width: 140,
    minWidth: 100,
    cellBuilder: (info) => IpAddresses(info.instanceInfo.ipv4.skip(1)),
  ),
];

class SelectAllCheckbox extends ConsumerWidget {
  const SelectAllCheckbox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedVms = ref.watch(selectedVmsProvider);
    final searchName = ref.watch(searchNameProvider);
    final runningOnly = ref.watch(runningOnlyProvider);
    final vmIds = ref
        .watch(vmInfosProvider)
        .where((i) => !runningOnly || i.instanceStatus.status == Status.RUNNING)
        .where((i) => i.name.contains(searchName))
        .map((i) => i.id)
        .toList();
    final allSelected = selectedVms.containsAll(vmIds);

    void toggleSelectedAll(bool isSelected) {
      final newState = isSelected ? vmIds.toBuiltSet() : BuiltSet<VmId>();
      ref.read(selectedVmsProvider.notifier).set(newState);
    }

    return Center(
      child: Checkbox(
        tristate: true,
        value: selectedVms.isEmpty ? false : (allSelected ? true : null),
        onChanged: (checked) => toggleSelectedAll(checked ?? false),
      ),
    );
  }
}

class SelectVmCheckbox extends ConsumerWidget {
  final VmId id;

  const SelectVmCheckbox(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      selectedVmsProvider.select((selectedVms) {
        return selectedVms.contains(id);
      }),
    );

    void toggleSelected(bool isSelected) {
      ref.read(selectedVmsProvider.notifier).toggle(id, isSelected);
    }

    return Center(
      child: Checkbox(
        value: selected,
        onChanged: (checked) => toggleSelected(checked!),
      ),
    );
  }
}

class VmNameLink extends ConsumerWidget {
  final VmId id;

  const VmNameLink(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    goToVm() {
      ref.read(vmScreenLocationProvider(id).notifier).set(VmDetailsLocation.details);
      ref.read(sidebarKeyProvider.notifier).set(id.sidebarKey);
    }

    return Tooltip(
      message: id.displayLabel,
      child: Row(
        children: [
          Flexible(
            child: Text.rich(
              id.name.nonBreaking.spanInherit.link(ref, goToVm),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DaemonSourceChip(id.source),
        ],
      ),
    );
  }
}

class VmShellLink extends ConsumerWidget {
  final VmId id;

  const VmShellLink(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    goToShell() {
      ref.read(vmScreenLocationProvider(id).notifier).set(VmDetailsLocation.shells);
      ref.read(sidebarKeyProvider.notifier).set(id.sidebarKey);
    }

    return Tooltip(
      message: l10n.vmTableColumnShell,
      child: IconButton(
        icon: const Icon(Icons.terminal, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: goToShell,
      ),
    );
  }
}

class DistroLogo extends StatelessWidget {
  final String os;
  final double size;
  final String? release;
  final Iterable<String>? aliases;
  final bool isCore;

  const DistroLogo(
    this.os, {
    this.size = 24,
    this.release,
    this.aliases,
    this.isCore = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final releaseText = release?.trim() ?? '';
    if (os.trim().isEmpty && releaseText.isEmpty) {
      return SizedBox(width: size, height: size);
    }

    final branding = distroBranding(
      os,
      release: release,
      isCore: isCore ||
          distroIsCore(os: os, release: release, aliases: aliases),
    );
    return DistroLogoBadge(branding: branding, size: size);
  }
}
