/*
 * Copyright (C) Elemento.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';
import '../l10n/app_localizations.dart';
import '../layout/compact_layout.dart';
import '../providers.dart';
import '../services/compose/compose_graph.dart';
import '../services/service_branding.dart';
import '../services/service_library.dart';
import '../services/service_status.dart';
import '../widgets/launchpad_button.dart';

/// A suggested guest destination derived from service provides / endpoints.
class DestinationPortHint {
  const DestinationPortHint({
    required this.port,
    required this.label,
    required this.icon,
    this.accent,
    this.detail,
  });

  final int port;
  final String label;
  final IconData icon;
  final Color? accent;
  final String? detail;
}

int? portFromEndpointValue(String value) {
  final trimmed = value.trim();
  final asInt = int.tryParse(trimmed);
  if (asInt != null && asInt >= 1 && asInt <= 65535) return asInt;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty && !trimmed.contains('://')) {
    // Bare host:port without scheme
    final match = RegExp(r':(\d{1,5})(?:/|$)').firstMatch(trimmed);
    if (match != null) {
      final port = int.tryParse(match.group(1)!);
      if (port != null && port >= 1 && port <= 65535) return port;
    }
    return null;
  }
  if (uri.hasPort) return uri.port;
  if (uri.scheme == 'https') return 443;
  if (uri.scheme == 'http') return 80;
  return null;
}

String endpointRoleLabel(String key) {
  final role = key.replaceFirst(RegExp(r'^local_'), '');
  return switch (role) {
    'ui' => 'Web UI',
    'api' => 'API',
    'console' => 'Console',
    'sandbox_api' => 'Sandbox API',
    'ca' => 'CA',
    'acme' => 'ACME',
    'catalog' => 'Catalog',
    'health' => 'Health',
    'port' => 'TCP port',
    'host' => 'Host',
    _ => role.replaceAll('_', ' '),
  };
}

IconData endpointRoleIcon(String key) {
  final role = key.replaceFirst(RegExp(r'^local_'), '');
  return switch (role) {
    'ui' => FontAwesomeIcons.windowMaximize,
    'api' || 'sandbox_api' || 'local_api' => FontAwesomeIcons.code,
    'console' => FontAwesomeIcons.gaugeHigh,
    'ca' || 'acme' || 'catalog' => FontAwesomeIcons.certificate,
    'health' => FontAwesomeIcons.heartPulse,
    'port' || 'host' => FontAwesomeIcons.database,
    _ => FontAwesomeIcons.plug,
  };
}

/// Prefer guest-local endpoints (explicit loopback ports) over public Caddy :443.
List<DestinationPortHint> destinationHintsForService({
  required MarketplaceService? template,
  ServiceInfoDocument? info,
  Color? accent,
}) {
  final byPort = <int, DestinationPortHint>{};

  void put(DestinationPortHint hint) {
    final existing = byPort[hint.port];
    if (existing == null) {
      byPort[hint.port] = hint;
      return;
    }
    // Prefer labels that come from local_* endpoints (more accurate guest ports).
    final preferNew = (hint.detail?.startsWith('local_') ?? false) &&
        !(existing.detail?.startsWith('local_') ?? false);
    if (preferNew) byPort[hint.port] = hint;
  }

  if (info != null) {
    final localEntries = info.endpoints.entries
        .where((e) => e.key.startsWith('local_'))
        .toList();
    final otherEntries = info.endpoints.entries
        .where((e) => !e.key.startsWith('local_'))
        .toList();

    for (final entry in [...localEntries, ...otherEntries]) {
      final port = portFromEndpointValue(entry.value);
      if (port == null) continue;
      // Skip public HTTPS default when a local_* already covers a real app port.
      if (!entry.key.startsWith('local_') &&
          (port == 443 || port == 80) &&
          localEntries.isNotEmpty) {
        continue;
      }
      put(DestinationPortHint(
        port: port,
        label: endpointRoleLabel(entry.key),
        icon: endpointRoleIcon(entry.key),
        accent: accent,
        detail: entry.key,
      ));
    }
  }

  final spec = template?.composeSpec;
  if (spec != null) {
    for (final contractId in composeOutputContracts(spec)) {
      final provides = spec.provides[contractId];
      if (provides == null) continue;
      for (final pointer in provides.outputs.values) {
        final endpointKey = pointer.split('/').where((p) => p.isNotEmpty).lastOrNull;
        if (endpointKey == null) continue;
        final live = info?.endpoints[endpointKey] ??
            info?.endpoints['local_$endpointKey'];
        final port = live == null ? null : portFromEndpointValue(live);
        if (port == null) continue;
        put(DestinationPortHint(
          port: port,
          label: composePinLabel(contractId),
          icon: endpointRoleIcon(endpointKey),
          accent: accent,
          detail: contractId,
        ));
      }
    }

    for (final output in composeHttpOutputs(spec)) {
      final parts =
          output.pointer.split('/').where((p) => p.isNotEmpty).toList();
      final key = parts.isEmpty ? output.pointer : parts.last;
      final live = info?.endpoints[key] ?? info?.endpoints['local_$key'];
      final port = live == null ? null : portFromEndpointValue(live);
      if (port == null) continue;
      put(DestinationPortHint(
        port: port,
        label: composeHttpOutputLabel(output),
        icon: endpointRoleIcon(key),
        accent: accent,
        detail: output.pointer,
      ));
    }
  }

  if (template != null) {
    for (final port in template.exposedPorts) {
      put(DestinationPortHint(
        port: port,
        label: 'Ingress',
        icon: FontAwesomeIcons.shieldHalved,
        accent: accent,
        detail: 'firewall:$port',
      ));
    }
  }

  final sorted = byPort.values.toList()
    ..sort((a, b) {
      final byLabel = a.label.compareTo(b.label);
      if (byLabel != 0) return byLabel;
      return a.port.compareTo(b.port);
    });
  return sorted;
}

const _commonHostPorts = [80, 443, 3000, 5000, 8080, 8443, 9000];

Future<void> showAddPortForwardDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _AddPortForwardDialog(),
  );
}

class _AddPortForwardDialog extends ConsumerStatefulWidget {
  const _AddPortForwardDialog();

  @override
  ConsumerState<_AddPortForwardDialog> createState() =>
      _AddPortForwardDialogState();
}

class _AddPortForwardDialogState extends ConsumerState<_AddPortForwardDialog> {
  final hostPortController = TextEditingController();
  final guestPortController = TextEditingController();
  final bindController = TextEditingController(text: '127.0.0.1');
  String? selectedInstance;
  int? selectedHostPort;
  int? selectedGuestPort;
  String? selectedHintKey;
  String? error;
  var saving = false;

  @override
  void dispose() {
    hostPortController.dispose();
    guestPortController.dispose();
    bindController.dispose();
    super.dispose();
  }

  void _selectHostPort(int port) {
    setState(() {
      selectedHostPort = port;
      hostPortController.text = '$port';
      error = null;
    });
  }

  void _selectGuestHint(DestinationPortHint hint) {
    setState(() {
      selectedGuestPort = hint.port;
      selectedHintKey = hint.detail ?? hint.label;
      guestPortController.text = '${hint.port}';
      // Default host port to the same value for one-click publish.
      if (selectedHostPort == null ||
          hostPortController.text.trim().isEmpty ||
          hostPortController.text.trim() == '${selectedGuestPort ?? ''}') {
        selectedHostPort = hint.port;
        hostPortController.text = '${hint.port}';
      }
      error = null;
    });
  }

  Future<void> _save(String instance) async {
    final l10n = AppLocalizations.of(context)!;
    final hostPort = int.tryParse(hostPortController.text.trim());
    final guestRaw = guestPortController.text.trim();
    final guestPort = guestRaw.isEmpty ? hostPort : int.tryParse(guestRaw);
    final bind = bindController.text.trim().isEmpty
        ? '127.0.0.1'
        : bindController.text.trim();

    if (hostPort == null || hostPort < 1 || hostPort > 65535) {
      setState(() => error = l10n.portForwardInvalidHostPort);
      return;
    }
    if (guestPort == null || guestPort < 1 || guestPort > 65535) {
      setState(() => error = l10n.portForwardInvalidGuestPort);
      return;
    }

    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref.read(grpcClientProvider).addPortForward(
            instance: instance,
            hostPort: hostPort,
            guestPort: guestPort,
            hostBind: bind,
          );
      ref.invalidate(allPortForwardsProvider);
      ref.invalidate(portForwardsProvider(instance));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final library = ref.watch(marketplaceLibraryProvider).asData?.value;
    final bindings = ref.watch(serviceInstanceBindingsProvider);

    final serviceInfos = ref.watch(serviceInstanceInfosProvider);
    final plainInfos = ref
        .watch(allActiveVmInfosWithServicesProvider)
        .where((info) =>
            info.source == DaemonSource.elp && !isServiceVmInfo(info.info))
        .toList();

    final targets = <_InstanceTarget>[
      for (final info in serviceInfos)
        _InstanceTarget(
          name: info.name,
          serviceId: effectiveServiceId(info.info, bindings),
          isService: true,
        ),
      for (final info in plainInfos)
        _InstanceTarget(name: info.name, serviceId: '', isService: false),
    ];

    if (targets.isEmpty) {
      return AlertDialog(
        shape: const Border(),
        title: Text(l10n.portForwardAdd),
        content: Text(l10n.portForwardNoInstances),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
        ],
      );
    }

    selectedInstance ??= targets.first.name;
    final selected = targets.firstWhere(
      (t) => t.name == selectedInstance,
      orElse: () => targets.first,
    );
    final template = selected.serviceId.isEmpty
        ? null
        : library?.lookup(selected.serviceId);
    final branding = selected.isService
        ? serviceBranding(selected.serviceId, service: template)
        : const ServiceBranding(
            icon: FontAwesomeIcons.server,
            accent: Brand.workloadVm,
          );

    final guestStatus = selected.isService
        ? ref.watch(serviceGuestStatusProvider(selected.name)).asData?.value
        : null;
    final hints = destinationHintsForService(
      template: template,
      info: guestStatus?.info,
      accent: branding.accent,
    );

    final hostChoices = <int>{
      ..._commonHostPorts,
      if (selectedHostPort != null) selectedHostPort!,
      if (selectedGuestPort != null) selectedGuestPort!,
      for (final hint in hints) hint.port,
    }.toList()
      ..sort();

    return AlertDialog(
      shape: const Border(),
      title: Text(l10n.portForwardAdd),
      content: SizedBox(
        width: CompactLayout.dialogWidth(context, 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.portForwardPickInstance,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: onSurface.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final target in targets)
                    _InstancePickTile(
                      target: target,
                      selected: target.name == selected.name,
                      branding: target.isService
                          ? serviceBranding(
                              target.serviceId,
                              service: library?.lookup(target.serviceId),
                            )
                          : const ServiceBranding(
                              icon: FontAwesomeIcons.server,
                              accent: Brand.workloadVm,
                            ),
                      displayName: target.isService
                          ? (library?.lookup(target.serviceId)?.displayName ??
                              target.serviceId)
                          : l10n.portForwardPlainVm,
                      onTap: () => setState(() {
                        selectedInstance = target.name;
                        selectedGuestPort = null;
                        selectedHintKey = null;
                        guestPortController.clear();
                        error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                l10n.portForwardPickDestination,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: onSurface.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.portForwardPickDestinationHint,
                style: TextStyle(
                  fontSize: 12,
                  color: onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              if (hints.isEmpty)
                Text(
                  l10n.portForwardNoDestinationHints,
                  style: TextStyle(color: onSurface.withValues(alpha: 0.55)),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final hint in hints)
                      _DestinationChip(
                        hint: hint,
                        selected: selectedHintKey == (hint.detail ?? hint.label) &&
                            selectedGuestPort == hint.port,
                        onTap: () => _selectGuestHint(hint),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              TextField(
                controller: guestPortController,
                decoration: InputDecoration(
                  labelText: l10n.portForwardGuestPort,
                  hintText: l10n.portForwardGuestPortHint,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  final port = int.tryParse(value);
                  setState(() {
                    selectedGuestPort = port;
                    selectedHintKey = null;
                  });
                },
              ),
              const SizedBox(height: 20),
              Text(
                l10n.portForwardPickHostPort,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: onSurface.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final port in hostChoices)
                    ChoiceChip(
                      label: Text(':$port'),
                      selected: selectedHostPort == port,
                      onSelected: (_) => _selectHostPort(port),
                      selectedColor: branding.accent.withValues(alpha: 0.22),
                      side: BorderSide(
                        color: selectedHostPort == port
                            ? branding.accent
                            : onSurface.withValues(alpha: 0.2),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hostPortController,
                decoration: InputDecoration(labelText: l10n.portForwardHostPort),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  setState(() => selectedHostPort = int.tryParse(value));
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bindController,
                decoration: InputDecoration(labelText: l10n.portForwardBind),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        LaunchPadButton.primary(
          onPressed: saving ? null : () => _save(selected.name),
          child: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.commonSave),
        ),
      ],
    );
  }
}

class _InstanceTarget {
  const _InstanceTarget({
    required this.name,
    required this.serviceId,
    required this.isService,
  });

  final String name;
  final String serviceId;
  final bool isService;
}

class _InstancePickTile extends StatelessWidget {
  const _InstancePickTile({
    required this.target,
    required this.selected,
    required this.branding,
    required this.displayName,
    required this.onTap,
  });

  final _InstanceTarget target;
  final bool selected;
  final ServiceBranding branding;
  final String displayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: selected
              ? branding.accent.withValues(alpha: 0.16)
              : onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(Brand.radius),
          border: Border.all(
            color: selected ? branding.accent : onSurface.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ServiceIconBadge(branding: branding, size: 28),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: onSurface.withValues(alpha: 0.55),
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

class _DestinationChip extends StatelessWidget {
  const _DestinationChip({
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final DestinationPortHint hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = hint.accent ?? Brand.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.18)
              : onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(Brand.radius),
          border: Border.all(
            color: selected ? accent : onSurface.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(hint.icon, size: 12, color: accent),
            const SizedBox(width: 8),
            Text(
              hint.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Text(
              ':${hint.port}',
              style: TextStyle(color: onSurface.withValues(alpha: 0.65)),
            ),
          ],
        ),
      ),
    );
  }
}
