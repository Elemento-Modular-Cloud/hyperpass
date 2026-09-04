import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../page_surface.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../vm_table/table.dart' as vmtable;
import 'service_instance_headers.dart';
import 'service_instance_id.dart';
import 'services_screen.dart';

class ServiceInstancesScreen extends ConsumerWidget {
  static const sidebarKey = serviceInstancesSidebarKey;

  const ServiceInstancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final instances = ref.watch(serviceInstanceInfosProvider);

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.serviceInstancesLabel,
              style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.serviceInstancesSubtitle,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: instances.isEmpty
                  ? const NoServiceInstances()
                  : vmtable.Table<TaggedVmInfo>(
                      key: ValueKey(
                        instances.map((i) => i.name).join(','),
                      ),
                      headers: serviceInstanceHeaders,
                      data: instances,
                      rowExtent: 36,
                      cellMargin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      finalRow: List.generate(
                        serviceInstanceHeaders.length,
                        (_) => const SizedBox.shrink(),
                      ),
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
