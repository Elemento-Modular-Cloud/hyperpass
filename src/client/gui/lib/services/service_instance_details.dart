import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../copyable_text.dart';
import '../delete_instance_dialog.dart';
import '../l10n/app_localizations.dart';
import '../notifications.dart';
import '../page_surface.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../vm_action.dart';
import '../vm_details/ip_addresses.dart';
import '../vm_details/terminal_tabs.dart';
import '../vm_details/vm_status_icon.dart';
import 'service_branding.dart';
import 'service_instances_screen.dart';
import 'service_library.dart';
import 'service_status.dart';

enum ServiceDetailsLocation { overview, shell }

final serviceScreenLocationProvider = NotifierProvider.autoDispose
    .family<ServiceScreenLocationNotifier, ServiceDetailsLocation, String>(
  ServiceScreenLocationNotifier.new,
);

class ServiceScreenLocationNotifier extends Notifier<ServiceDetailsLocation> {
  ServiceScreenLocationNotifier(this.instanceName);
  final String instanceName;

  @override
  ServiceDetailsLocation build() => ServiceDetailsLocation.overview;

  void set(ServiceDetailsLocation location) {
    state = location;
  }
}

class ServiceInstanceDetailsScreen extends ConsumerWidget {
  const ServiceInstanceDetailsScreen(this.instanceName, {super.key});

  final String instanceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final id = elpVm(instanceName);
    final info = ref
        .watch(serviceInstanceInfosProvider)
        .where((i) => i.name == instanceName)
        .firstOrNull;
    final launching = ref.watch(isLaunchingProvider(id));
    final guestStatus = ref.watch(serviceGuestStatusProvider(instanceName));
    final location = ref.watch(serviceScreenLocationProvider(instanceName));

    if (info == null) {
      return Scaffold(
        body: PageSurface(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.serviceInstanceMissing(instanceName)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref
                      .read(sidebarKeyProvider.notifier)
                      .set(ServiceInstancesScreen.sidebarKey),
                  child: Text(l10n.serviceInstancesLabel),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final serviceId = info.info.serviceId;
    final library = ref.watch(marketplaceLibraryProvider).asData?.value;
    final template = library?.lookup(serviceId);
    final branding = serviceBranding(serviceId, service: template);
    final displayName = template?.displayName ?? serviceId;
    final status = info.instanceStatus.status;
    final buttonStyle = Theme.of(context).outlinedButtonTheme.style;

    OutlinedButton locationButton(ServiceDetailsLocation tab) {
      final selected = location == tab;
      final label = switch (tab) {
        ServiceDetailsLocation.overview => l10n.serviceDetailsOverview,
        ServiceDetailsLocation.shell => l10n.serviceDetailsShell,
      };
      return OutlinedButton(
        style: buttonStyle?.copyWith(
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
          backgroundColor:
              selected ? const WidgetStatePropertyAll(Color(0xff333333)) : null,
          foregroundColor:
              selected ? const WidgetStatePropertyAll(Colors.white) : null,
        ),
        onPressed: () => ref
            .read(serviceScreenLocationProvider(instanceName).notifier)
            .set(tab),
        child: Text(label),
      );
    }

    final header = Row(
      children: [
        IconButton(
          tooltip: l10n.serviceInstancesLabel,
          onPressed: () => ref
              .read(sidebarKeyProvider.notifier)
              .set(ServiceInstancesScreen.sidebarKey),
          icon: const Icon(Icons.arrow_back),
        ),
        ServiceIconBadge(branding: branding, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                instanceName,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                ),
              ),
              Text(
                displayName,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            locationButton(ServiceDetailsLocation.overview),
            locationButton(ServiceDetailsLocation.shell),
          ],
        ),
        const SizedBox(width: 16),
        TextButton(
          onPressed: () => ref
              .read(serviceScreenLocationProvider(instanceName).notifier)
              .set(ServiceDetailsLocation.shell),
          child: Text(l10n.terminalOpenShell),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 140,
          child: VmStatusIcon(status, isLaunching: launching),
        ),
      ],
    );

    final overview = ListView(
      children: [
        _ServiceInstanceActions(id: id, status: status),
        const Divider(height: 32),
        Text(
          l10n.serviceInstanceHealthTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        guestStatus.when(
          loading: () => Text(l10n.serviceHealthChecking),
          error: (e, _) => Text('$e'),
          data: (s) => _HealthSummary(status: s),
        ),
        const Divider(height: 32),
        Text(
          l10n.serviceInstanceConnectionTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        guestStatus.when(
          loading: () => Text(l10n.serviceHealthChecking),
          error: (e, _) => Text('$e'),
          data: (s) => _ConnectionInfoSection(status: s),
        ),
        const Divider(height: 32),
        Text(
          l10n.serviceInstanceVmTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _LabeledCopyable(
          label: l10n.serviceInstancesColumnName,
          value: instanceName,
        ),
        _LabeledCopyable(
          label: l10n.serviceInstancesColumnService,
          value: serviceId,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  l10n.serviceInstancesColumnIpv4,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                  ),
                ),
              ),
              Expanded(child: IpAddresses(info.instanceInfo.ipv4)),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 16),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Visibility(
                    visible: location == ServiceDetailsLocation.overview,
                    maintainState: true,
                    child: overview,
                  ),
                  Visibility(
                    visible: location == ServiceDetailsLocation.shell,
                    maintainState: true,
                    child: TerminalTabs(id),
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

class _ServiceInstanceActions extends ConsumerWidget {
  const _ServiceInstanceActions({required this.id, required this.status});

  final VmId id;
  final Status status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final client = ref.read(grpcClientProvider);

    void run(VmAction action, Future<void> Function() op) {
      ref.read(notificationsProvider.notifier).addOperation(
            op(),
            loading: l10n.bulkActionMessage(
              action.continuousTense(l10n),
              id.name,
            ),
            onSuccess: (_) =>
                l10n.bulkActionMessage(action.pastTense(l10n), id.name),
            onError: (error) => l10n.bulkActionError(
              action.label(l10n).toLowerCase(),
              id.name,
              '$error',
            ),
          );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        VmActionButton(
          action: VmAction.start,
          currentStatuses: [status],
          function: () => run(VmAction.start, () => client.start([id.name])),
        ),
        VmActionButton(
          action: VmAction.stop,
          currentStatuses: [status],
          function: () => run(VmAction.stop, () => client.stop([id.name])),
        ),
        VmActionButton(
          action: VmAction.restart,
          currentStatuses: [status],
          function: () =>
              run(VmAction.restart, () => client.restart([id.name])),
        ),
        VmActionButton(
          action: VmAction.delete,
          currentStatuses: [status],
          function: () {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => DeleteInstanceDialog(
                onDelete: () {
                  run(VmAction.delete, () => client.purge([id.name]));
                  ref
                      .read(serviceInstanceBindingsProvider.notifier)
                      .unbind(id.name);
                  ref
                      .read(sidebarKeyProvider.notifier)
                      .set(ServiceInstancesScreen.sidebarKey);
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HealthSummary extends StatelessWidget {
  const _HealthSummary({required this.status});

  final ServiceGuestStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        if (status.healthDetail != null && status.healthDetail!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            status.healthDetail!,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7),
            ),
          ),
        ],
        if (status.info?.status.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          _LabeledCopyable(
            label: l10n.serviceInstanceInfoStatus,
            value: status.info!.status,
          ),
        ],
      ],
    );
  }
}

class _ConnectionInfoSection extends StatelessWidget {
  const _ConnectionInfoSection({required this.status});

  final ServiceGuestStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final info = status.info;

    if (info == null) {
      return Text(
        status.infoError ?? l10n.serviceInstanceConnectionUnavailable,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (info.endpoints.isNotEmpty) ...[
          Text(
            l10n.serviceInstanceEndpoints,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final entry in info.endpoints.entries)
            _EndpointRow(label: entry.key, value: entry.value),
          const SizedBox(height: 12),
        ],
        if (info.credentials.isNotEmpty) ...[
          Text(
            l10n.serviceInstanceCredentials,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final entry in info.credentials.entries)
            _LabeledCopyable(label: entry.key, value: entry.value),
          const SizedBox(height: 12),
        ],
        if (info.backends.isNotEmpty) ...[
          Text(
            l10n.serviceInstanceBackends,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < info.backends.length; i++)
            for (final entry in info.backends[i].entries)
              _LabeledCopyable(
                label: info.backends.length == 1
                    ? entry.key
                    : '${entry.key} (${i + 1})',
                value: entry.value,
              ),
        ],
        if (info.endpoints.isEmpty &&
            info.credentials.isEmpty &&
            info.backends.isEmpty)
          Text(l10n.serviceInstanceConnectionEmpty),
      ],
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(value);
    final canOpen = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
          ),
          Expanded(child: CopyableText(value)),
          if (canOpen)
            IconButton(
              tooltip: AppLocalizations.of(context)!.serviceInstanceOpenUrl,
              onPressed: () => launchUrl(uri),
              icon: const Icon(Icons.open_in_new, size: 18),
            ),
        ],
      ),
    );
  }
}

class _LabeledCopyable extends StatelessWidget {
  const _LabeledCopyable({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
          ),
          Expanded(child: CopyableText(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}
