import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand.dart';
import '../daemon_source.dart';
import '../delete_instance_dialog.dart';
import '../l10n/app_localizations.dart';
import '../notifications.dart';
import '../providers.dart';
import '../vm_action.dart';

class VmActionButtons extends ConsumerWidget {
  final VmId id;

  const VmActionButtons(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final name = id.name;
    final client = switch (id.source) {
      DaemonSource.elp => ref.watch(grpcClientProvider),
      DaemonSource.multipass => ref.watch(multipassGrpcClientProvider),
    };

    Function(VmAction) wrapInNotification(
      Future<void> Function(Iterable<String>) function,
    ) {
      return (action) {
        final notificationsNotifier = ref.read(notificationsProvider.notifier);
        notificationsNotifier.addOperation(
          function([name]),
          loading:
              l10n.vmActionNotification(action.continuousTense(l10n), name),
          onSuccess: (_) =>
              l10n.vmActionNotification(action.pastTense(l10n), name),
          onError: (error) {
            return l10n.vmActionNotificationError(
                action.name.toLowerCase(), name, '$error');
          },
        );
      };
    }

    final actions = <VmAction, void Function(VmAction)>{
      if (client != null) ...{
        VmAction.start: wrapInNotification(client.start),
        VmAction.stop: wrapInNotification(client.stop),
        VmAction.suspend: wrapInNotification(client.suspend),
        VmAction.delete: (action) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => DeleteInstanceDialog(
              onDelete: () => wrapInNotification(client.purge)(action),
            ),
          );
        },
        VmAction.forceDelete: (action) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => DeleteInstanceDialog(
              force: true,
              onDelete: () => wrapInNotification(client.purge)(action),
            ),
          );
        },
      },
    };

    final actionButtons = [
      for (final MapEntry(key: action, value: function) in actions.entries)
        PopupMenuItem(
          padding: EdgeInsets.zero,
          enabled: false,
          child: ActionTile(id, action, () => function(action)),
        ),
    ];

    return PopupMenuButton(
      tooltip: l10n.vmActionsMenuTooltip,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => actionButtons,
      child: Builder(
        builder: (context) {
          final onSurface = Theme.of(context).colorScheme.onSurface;
          return Container(
            width: 110,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radius),
              border: Border.all(color: onSurface.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  l10n.vmActionsMenuTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: onSurface, size: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ActionTile extends ConsumerWidget {
  final VmId id;
  final VmAction action;
  final VoidCallback function;

  const ActionTile(this.id, this.action, this.function, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      vmInfoProvider(id).select((info) {
        return action.allowedStatuses.contains(info.instanceStatus.status);
      }),
    );

    return ListTile(
      enabled: enabled,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        action.label(AppLocalizations.of(context)!),
        style: TextStyle(
          color: enabled
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
        ),
      ),
      onTap: enabled
          ? () {
              Navigator.pop(context);
              function();
            }
          : null,
    );
  }
}
