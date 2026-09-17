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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../copyable_text.dart';
import '../l10n/app_localizations.dart';
import '../notifications/notifications_provider.dart';
import '../port_forwards/add_port_forward_dialog.dart';
import '../providers.dart';
import '../services/service_branding.dart';
import '../services/service_library.dart';
import '../services/service_status.dart';
import '../widgets/launchpad_button.dart';

/// Host→guest L4 TCP port forwards for a single instance.
class PortForwardsDetails extends ConsumerStatefulWidget {
  final String instanceName;
  final List<int> suggestedGuestPorts;
  final String? serviceId;

  const PortForwardsDetails({
    super.key,
    required this.instanceName,
    this.suggestedGuestPorts = const [],
    this.serviceId,
  });

  @override
  ConsumerState<PortForwardsDetails> createState() => _PortForwardsDetailsState();
}

class _PortForwardsDetailsState extends ConsumerState<PortForwardsDetails> {
  final hostPortController = TextEditingController();
  final guestPortController = TextEditingController();
  final bindController = TextEditingController(text: '127.0.0.1');
  var adding = false;
  String? selectedHintKey;

  @override
  void dispose() {
    hostPortController.dispose();
    guestPortController.dispose();
    bindController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final hostPort = int.tryParse(hostPortController.text.trim());
    final guestRaw = guestPortController.text.trim();
    final guestPort = guestRaw.isEmpty ? (hostPort ?? 0) : int.tryParse(guestRaw);
    final bind = bindController.text.trim().isEmpty ? '127.0.0.1' : bindController.text.trim();

    if (hostPort == null || hostPort < 1 || hostPort > 65535) {
      return;
    }
    if (guestPort == null || guestPort < 1 || guestPort > 65535) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final op = ref.read(grpcClientProvider).addPortForward(
          instance: widget.instanceName,
          hostPort: hostPort,
          guestPort: guestPort,
          hostBind: bind,
        );
    ref.read(notificationsProvider.notifier).addOperation(
          op,
          loading: l10n.portForwardAdding,
          onSuccess: (_) {
            hostPortController.clear();
            guestPortController.clear();
            setState(() {
              adding = false;
              selectedHintKey = null;
            });
            ref.invalidate(portForwardsProvider(widget.instanceName));
            ref.invalidate(allPortForwardsProvider);
            return l10n.portForwardAdded;
          },
          onError: (e) => '$e',
        );
  }

  Future<void> _remove(PortForward forward) async {
    final l10n = AppLocalizations.of(context)!;
    final op = ref.read(grpcClientProvider).removePortForward(forward.id);
    ref.read(notificationsProvider.notifier).addOperation(
          op,
          loading: l10n.portForwardRemoving,
          onSuccess: (_) {
            ref.invalidate(portForwardsProvider(widget.instanceName));
            ref.invalidate(allPortForwardsProvider);
            return l10n.portForwardRemoved;
          },
          onError: (e) => '$e',
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final forwardsAsync = ref.watch(portForwardsProvider(widget.instanceName));
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final library = ref.watch(marketplaceLibraryProvider).asData?.value;
    final serviceId = widget.serviceId ?? '';
    final template =
        serviceId.isEmpty ? null : library?.lookup(serviceId);
    final branding = serviceId.isEmpty
        ? null
        : serviceBranding(serviceId, service: template);
    final guestStatus = serviceId.isEmpty
        ? null
        : ref.watch(serviceGuestStatusProvider(widget.instanceName)).asData?.value;
    final hints = destinationHintsForService(
      template: template,
      info: guestStatus?.info,
      accent: branding?.accent,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.portForwardsTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.portForwardsSubtitle,
          style: TextStyle(color: onSurface.withValues(alpha: 0.65)),
        ),
        const SizedBox(height: 12),
        forwardsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (forwards) {
            if (forwards.isEmpty && !adding) {
              return Text(
                l10n.portForwardsEmpty,
                style: TextStyle(color: onSurface.withValues(alpha: 0.65)),
              );
            }
            return Column(
              children: [
                for (final forward in forwards)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: CopyableText(
                            '${forward.hostBind}:${forward.hostPort} → '
                            '${forward.guestIp.isEmpty ? widget.instanceName : forward.guestIp}:'
                            '${forward.guestPort}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          forward.active ? l10n.portForwardActive : l10n.portForwardInactive,
                          style: TextStyle(
                            color: forward.active
                                ? Theme.of(context).colorScheme.primary
                                : onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.commonDelete,
                          onPressed: () => _remove(forward),
                          icon: const Icon(Icons.delete_outline, size: 20),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        if (hints.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final hint in hints)
                ActionChip(
                  avatar: FaIcon(hint.icon, size: 12, color: hint.accent),
                  label: Text('${hint.label} :${hint.port}'),
                  backgroundColor: selectedHintKey == (hint.detail ?? hint.label)
                      ? (hint.accent ?? Theme.of(context).colorScheme.primary)
                          .withValues(alpha: 0.18)
                      : null,
                  side: BorderSide(
                    color: selectedHintKey == (hint.detail ?? hint.label)
                        ? (hint.accent ?? Theme.of(context).colorScheme.primary)
                        : onSurface.withValues(alpha: 0.2),
                  ),
                  onPressed: () {
                    setState(() {
                      adding = true;
                      selectedHintKey = hint.detail ?? hint.label;
                      guestPortController.text = '${hint.port}';
                      if (hostPortController.text.isEmpty) {
                        hostPortController.text = '${hint.port}';
                      }
                    });
                  },
                ),
            ],
          ),
        ] else if (widget.suggestedGuestPorts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final port in widget.suggestedGuestPorts)
                ActionChip(
                  label: Text(l10n.portForwardSuggestPort(port)),
                  onPressed: () {
                    setState(() {
                      adding = true;
                      guestPortController.text = '$port';
                      if (hostPortController.text.isEmpty) {
                        hostPortController.text = '$port';
                      }
                    });
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (adding)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: TextField(
                  controller: hostPortController,
                  decoration: InputDecoration(labelText: l10n.portForwardHostPort),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: guestPortController,
                  decoration: InputDecoration(
                    labelText: l10n.portForwardGuestPort,
                    hintText: l10n.portForwardGuestPortHint,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: bindController,
                  decoration: InputDecoration(labelText: l10n.portForwardBind),
                ),
              ),
              const SizedBox(width: 12),
              LaunchPadButton.primary(
                onPressed: _add,
                child: Text(l10n.commonSave),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => setState(() {
                  adding = false;
                  selectedHintKey = null;
                }),
                child: Text(l10n.commonCancel),
              ),
            ],
          )
        else
          OutlinedButton(
            onPressed: () => setState(() => adding = true),
            child: Text(l10n.portForwardAdd),
          ),
      ],
    );
  }
}
