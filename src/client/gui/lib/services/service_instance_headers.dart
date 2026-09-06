import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../tooltip.dart';
import '../vm_details/ip_addresses.dart';
import '../vm_details/vm_status_icon.dart';
import '../vm_table/search_box.dart';
import '../vm_table/table.dart';
import 'service_branding.dart';
import 'service_instance_details.dart';
import 'service_instance_id.dart';
import 'service_library.dart';
import 'service_selection.dart';
import 'service_status.dart';

Widget Function(String) _l10nHeader(String Function(AppLocalizations) label) {
  return (_) => Builder(
        builder: (context) => TableHeader.defaultHeaderBuilder(
            label(AppLocalizations.of(context)!)),
      );
}

final serviceInstanceHeaders = <TableHeader<TaggedVmInfo>>[
  TableHeader(
    name: 'checkbox',
    childBuilder: (_) => const SelectAllServiceCheckbox(),
    width: 50,
    minWidth: 50,
    cellBuilder: (info) => SelectServiceCheckbox(info.id),
  ),
  TableHeader(
    name: 'NAME',
    childBuilder: _l10nHeader((l10n) => l10n.serviceInstancesColumnName),
    width: 160,
    minWidth: 100,
    sortKey: (info) => info.name,
    cellBuilder: (info) => ServiceInstanceNameLink(info),
  ),
  TableHeader(
    name: 'SHELL',
    childBuilder: _l10nHeader((l10n) => l10n.vmTableColumnShell),
    width: 56,
    minWidth: 48,
    cellBuilder: (info) => ServiceShellLink(info.name),
  ),
  TableHeader(
    name: 'SERVICE',
    childBuilder: _l10nHeader((l10n) => l10n.serviceInstancesColumnService),
    width: 180,
    minWidth: 120,
    sortKey: (info) => info.info.serviceId,
    cellBuilder: (info) => ServiceTemplateLabel(info.info.serviceId),
  ),
  TableHeader(
    name: 'STATE',
    childBuilder: _l10nHeader((l10n) => l10n.serviceInstancesColumnState),
    width: 120,
    minWidth: 80,
    sortKey: (info) => info.instanceStatus.status.name,
    cellBuilder: (info) => Consumer(
      builder: (context, ref, _) {
        final launching = ref.watch(isLaunchingProvider(info.id));
        return VmStatusIcon(
          info.instanceStatus.status,
          isLaunching: launching,
        );
      },
    ),
  ),
  TableHeader(
    name: 'HEALTH',
    childBuilder: _l10nHeader((l10n) => l10n.serviceInstancesColumnHealth),
    width: 120,
    minWidth: 80,
    cellBuilder: (info) => ServiceHealthCell(info.name),
  ),
  TableHeader(
    name: 'IPV4',
    childBuilder: _l10nHeader((l10n) => l10n.serviceInstancesColumnIpv4),
    width: 160,
    minWidth: 100,
    cellBuilder: (info) => IpAddresses(info.instanceInfo.ipv4),
  ),
];

class SelectAllServiceCheckbox extends ConsumerWidget {
  const SelectAllServiceCheckbox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedServiceInstancesProvider);
    final search = ref.watch(serviceSearchProvider);
    final ids = ref
        .watch(serviceInstanceInfosProvider)
        .where((i) {
          if (search.isEmpty) return true;
          final q = search.toLowerCase();
          return i.name.toLowerCase().contains(q) ||
              i.info.serviceId.toLowerCase().contains(q);
        })
        .map((i) => i.id)
        .toList();
    final allSelected = ids.isNotEmpty && selected.containsAll(ids);

    return Center(
      child: Checkbox(
        tristate: true,
        value: selected.isEmpty ? false : (allSelected ? true : null),
        onChanged: (checked) {
          ref.read(selectedServiceInstancesProvider.notifier).set(
                checked ?? false ? ids.toBuiltSet() : BuiltSet(),
              );
        },
      ),
    );
  }
}

class SelectServiceCheckbox extends ConsumerWidget {
  const SelectServiceCheckbox(this.id, {super.key});

  final VmId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      selectedServiceInstancesProvider.select((s) => s.contains(id)),
    );
    return Center(
      child: Checkbox(
        value: selected,
        onChanged: (checked) => ref
            .read(selectedServiceInstancesProvider.notifier)
            .toggle(id, checked!),
      ),
    );
  }
}

class ServiceShellLink extends ConsumerWidget {
  const ServiceShellLink(this.instanceName, {super.key});

  final String instanceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: l10n.terminalOpenShell,
      child: IconButton(
        icon: const Icon(Icons.terminal, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: () {
          ref
              .read(serviceScreenLocationProvider(instanceName).notifier)
              .set(ServiceDetailsLocation.shell);
          ref
              .read(sidebarKeyProvider.notifier)
              .set(serviceInstanceSidebarKey(instanceName));
        },
      ),
    );
  }
}

class ServiceInstanceNameLink extends ConsumerWidget {
  const ServiceInstanceNameLink(this.info, {super.key});

  final TaggedVmInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => ref
            .read(sidebarKeyProvider.notifier)
            .set(serviceInstanceSidebarKey(info.name)),
        child: Text(
          info.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class ServiceTemplateLabel extends ConsumerWidget {
  const ServiceTemplateLabel(this.serviceId, {super.key});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(marketplaceLibraryProvider).asData?.value;
    final template = library?.byId(serviceId);
    final branding = serviceBranding(serviceId);
    final label = template?.displayName ?? serviceId;

    return Row(
      children: [
        ServiceIconBadge(branding: branding, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: serviceId,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

class ServiceHealthCell extends ConsumerWidget {
  const ServiceHealthCell(this.instanceName, {super.key});

  final String instanceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(serviceGuestStatusProvider(instanceName));

    return async.when(
      loading: () => Text(l10n.serviceHealthChecking),
      error: (_, __) => Text(l10n.serviceHealthUnknown),
      data: (status) {
        final label = switch (status.health) {
          ServiceHealthState.healthy => l10n.serviceHealthHealthy,
          ServiceHealthState.unhealthy => l10n.serviceHealthUnhealthy,
          ServiceHealthState.unreachable => l10n.serviceHealthUnreachable,
          ServiceHealthState.unknown => l10n.serviceHealthUnknown,
        };
        final color = switch (status.health) {
          ServiceHealthState.healthy => const Color(0xff0C8420),
          ServiceHealthState.unhealthy => const Color(0xffC7162B),
          ServiceHealthState.unreachable => const Color(0xffC7162B),
          ServiceHealthState.unknown => const Color(0xff8A8D95),
        };
        return Text(label, style: TextStyle(color: color));
      },
    );
  }
}
