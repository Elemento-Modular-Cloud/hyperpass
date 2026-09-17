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

import 'package:flutter/material.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../copyable_text.dart';
import '../l10n/app_localizations.dart';
import '../notifications.dart';
import '../page_surface.dart';
import '../providers.dart';
import '../vm_table/table.dart';
import '../widgets/launchpad_button.dart';
import 'add_port_forward_dialog.dart';

/// Global host→guest L4 routing table (all instances).
class PortForwardsScreen extends ConsumerWidget {
  static const sidebarKey = 'port-forwards';

  const PortForwardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final forwardsAsync = ref.watch(allPortForwardsProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.portForwardsScreenTitle,
                    style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
                  ),
                ),
                IconButton(
                  tooltip: l10n.portForwardsRefresh,
                  onPressed: () => ref.invalidate(allPortForwardsProvider),
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                LaunchPadButton.primary(
                  onPressed: () => showAddPortForwardDialog(context, ref),
                  child: Text(l10n.portForwardAdd),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.portForwardsScreenSubtitle,
              style: TextStyle(fontSize: 14, color: onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: forwardsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('$error')),
                data: (forwards) => forwards.isEmpty
                    ? Center(
                        child: Text(
                          l10n.portForwardsEmpty,
                          style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
                        ),
                      )
                    : _RoutingTable(forwards: forwards),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutingTable extends ConsumerWidget {
  const _RoutingTable({required this.forwards});

  final List<PortForward> forwards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final headers = <TableHeader<PortForward>>[
      TableHeader(
        name: 'HOST',
        childBuilder: (_) => TableHeader.defaultHeaderBuilder(l10n.portForwardColHost),
        width: 180,
        minWidth: 120,
        sortKey: (f) => '${f.hostBind}:${f.hostPort.toString().padLeft(5, '0')}',
        cellBuilder: (f) => CopyableText('${f.hostBind}:${f.hostPort}'),
      ),
      TableHeader(
        name: 'INSTANCE',
        childBuilder: (_) => TableHeader.defaultHeaderBuilder(l10n.portForwardColInstance),
        width: 160,
        minWidth: 100,
        sortKey: (f) => f.instance,
        cellBuilder: (f) => CopyableText(f.instance),
      ),
      TableHeader(
        name: 'GUEST',
        childBuilder: (_) => TableHeader.defaultHeaderBuilder(l10n.portForwardColGuest),
        width: 180,
        minWidth: 120,
        sortKey: (f) =>
            '${f.guestIp.isEmpty ? '~' : f.guestIp}:${f.guestPort.toString().padLeft(5, '0')}',
        cellBuilder: (f) {
          final ip = f.guestIp.isEmpty ? '—' : f.guestIp;
          return CopyableText('$ip:${f.guestPort}');
        },
      ),
      TableHeader(
        name: 'STATUS',
        childBuilder: (_) => TableHeader.defaultHeaderBuilder(l10n.portForwardColStatus),
        width: 200,
        minWidth: 120,
        sortKey: (f) => f.active ? '0' : '1${f.statusMessage}',
        cellBuilder: (f) {
          final label = f.active ? l10n.portForwardActive : l10n.portForwardInactive;
          final detail = f.statusMessage.isEmpty ? label : '$label · ${f.statusMessage}';
          return Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: f.active
                  ? Theme.of(context).colorScheme.primary
                  : onSurface.withValues(alpha: 0.55),
            ),
          );
        },
      ),
      TableHeader(
        name: 'ACTIONS',
        childBuilder: (_) => TableHeader.defaultHeaderBuilder(l10n.portForwardColActions),
        width: 72,
        minWidth: 56,
        cellBuilder: (f) => Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _remove(context, ref, f),
          ),
        ),
      ),
    ];

    return Table(
      headers: headers,
      data: forwards,
      finalRow: const [],
    );
  }

  void _remove(BuildContext context, WidgetRef ref, PortForward forward) {
    final l10n = AppLocalizations.of(context)!;
    final op = ref.read(grpcClientProvider).removePortForward(forward.id);
    ref.read(notificationsProvider.notifier).addOperation(
          op,
          loading: l10n.portForwardRemoving,
          onSuccess: (_) {
            ref.invalidate(allPortForwardsProvider);
            ref.invalidate(portForwardsProvider(forward.instance));
            return l10n.portForwardRemoved;
          },
          onError: (e) => '$e',
        );
  }
}
