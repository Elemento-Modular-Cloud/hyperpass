import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../page_surface.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../vm_table/search_box.dart';
import '../vm_table/table.dart' as vmtable;
import '../llm/host_resource_gauges.dart';
import '../widgets/running_list_header.dart';
import 'service_bulk_actions.dart';
import 'service_instance_headers.dart';
import 'service_instance_id.dart';
import 'service_selection.dart';
import 'services_screen.dart';

class ServiceInstancesScreen extends ConsumerWidget {
  static const sidebarKey = serviceInstancesSidebarKey;

  const ServiceInstancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final search = ref.watch(serviceSearchProvider);
    final selected = ref.watch(selectedServiceInstancesProvider);
    final allInstances = ref.watch(serviceInstanceInfosProvider);
    final instances = allInstances
        .where((i) {
          if (search.isEmpty) return true;
          final q = search.toLowerCase();
          return i.name.toLowerCase().contains(q) ||
              i.info.serviceId.toLowerCase().contains(q);
        })
        .toList(growable: false);

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RunningListHeader(
              title: l10n.serviceInstancesLabel,
              subtitle: l10n.serviceInstancesSubtitle,
              action: TextButton(
                onPressed: () => ref
                    .read(sidebarKeyProvider.notifier)
                    .set(ServicesScreen.sidebarKey),
                child: Text(l10n.serviceDeployAction),
              ),
            ),
            const SizedBox(height: 8),
            const HostResourceGauges(),
            const SizedBox(height: 16),
            Expanded(
              child: allInstances.isEmpty
                  ? const NoServiceInstances()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Spacer(),
                            SearchBox(
                              key: const ValueKey('service-search'),
                              hint: l10n.searchBoxHintDeployments,
                              provider: serviceSearchProvider,
                            ),
                          ],
                        ),
                        const ServiceBulkActionsBar(),
                        const SizedBox(height: 10),
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: SizedBox(
                              height: (instances.length + 2) * 50,
                              width: double.infinity,
                              child: vmtable.Table<TaggedVmInfo>(
                                key: ValueKey(
                                  instances.map((i) => i.name).join(','),
                                ),
                                headers: serviceInstanceHeaders,
                                data: instances,
                                finalRow: List.generate(
                                  serviceInstanceHeaders.length,
                                  (_) => const SizedBox.shrink(),
                                ),
                                isSelected: (info) => selected.contains(info.id),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoServiceInstances extends ConsumerWidget {
  const NoServiceInstances({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.serviceInstancesEmpty,
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(l10n.serviceInstancesEmptyHint),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref
                .read(sidebarKeyProvider.notifier)
                .set(ServicesScreen.sidebarKey),
            child: Text(l10n.servicesLabel),
          ),
        ],
      ),
    );
  }
}
