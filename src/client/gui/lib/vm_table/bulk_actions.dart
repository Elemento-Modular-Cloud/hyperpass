import 'package:basics/basics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daemon_source.dart';
import '../delete_instance_dialog.dart';
import '../extensions.dart';
import '../l10n/app_localizations.dart';
import '../notifications.dart';
import '../providers.dart';
import '../vm_action.dart';
import 'vms.dart';

class BulkActionsBar extends ConsumerWidget {
  const BulkActionsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedVms = ref.watch(selectedVmsProvider);
    final statuses = ref
        .watch(vmStatusesProvider)
        .asMap()
        .whereKey(selectedVms.contains)
        .values
        .toSet();

    final l10n = AppLocalizations.of(context)!;

    GrpcClient? clientFor(DaemonSource source) => switch (source) {
          DaemonSource.elp => ref.read(grpcClientProvider),
          DaemonSource.multipass => ref.read(multipassGrpcClientProvider),
        };

    Function(VmAction) wrapInNotification(
      Future<void> Function(GrpcClient client, Iterable<String> names) function,
    ) {
      return (action) {
        final object = selectedVms.length == 1
            ? selectedVms.first.name
            : l10n.bulkActionInstanceCount(selectedVms.length);

        final notificationsNotifier = ref.read(notificationsProvider.notifier);
        notificationsNotifier.addOperation(
          runManagedAction(
            clientFor: clientFor,
            ids: selectedVms,
            action: function,
          ),
          loading: l10n.bulkActionMessage(action.continuousTense(l10n), object),
          onSuccess: (_) =>
              l10n.bulkActionMessage(action.pastTense(l10n), object),
          onError: (error) {
            return l10n.bulkActionError(
                action.label(l10n).toLowerCase(), object, '$error');
          },
        );
      };
    }

    final actions = {
      VmAction.start: wrapInNotification((c, names) => c.start(names)),
      VmAction.stop: wrapInNotification((c, names) => c.stop(names)),
      VmAction.suspend: wrapInNotification((c, names) => c.suspend(names)),
      VmAction.delete: (action) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => DeleteInstanceDialog(
            count: selectedVms.length,
            onDelete: () =>
                wrapInNotification((c, names) => c.purge(names))(action),
          ),
        );
      },
      VmAction.forceDelete: (action) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => DeleteInstanceDialog(
            force: true,
            count: selectedVms.length,
            onDelete: () =>
                wrapInNotification((c, names) => c.purge(names))(action),
          ),
        );
      },
    };

    final actionButtons = [
      for (final MapEntry(key: action, value: function) in actions.entries)
        VmActionButton(
          action: action,
          currentStatuses: statuses,
          function: () => function(action),
        ),
    ];

    return Row(children: actionButtons.gap(width: 8).toList());
  }
}
