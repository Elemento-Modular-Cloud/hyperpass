import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../delete_instance_dialog.dart';
import '../extensions.dart';
import '../l10n/app_localizations.dart';
import '../notifications.dart';
import '../providers.dart';
import '../vm_action.dart';
import 'service_selection.dart';

class ServiceBulkActionsBar extends ConsumerWidget {
  const ServiceBulkActionsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedServiceInstancesProvider);
    final infos = {
      for (final info in ref.watch(serviceInstanceInfosProvider)) info.id: info,
    };
    final statuses = selected
        .map((id) => infos[id]?.instanceStatus.status)
        .whereType<Status>()
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
        final object = selected.length == 1
            ? selected.first.name
            : l10n.bulkActionInstanceCount(selected.length);

        ref.read(notificationsProvider.notifier).addOperation(
              runManagedAction(
                clientFor: clientFor,
                ids: selected,
                action: function,
              ),
              loading:
                  l10n.bulkActionMessage(action.continuousTense(l10n), object),
              onSuccess: (_) =>
                  l10n.bulkActionMessage(action.pastTense(l10n), object),
              onError: (error) {
                return l10n.bulkActionError(
                  action.label(l10n).toLowerCase(),
                  object,
                  '$error',
                );
              },
            );
      };
    }

    final actions = <VmAction, void Function(VmAction)>{
      VmAction.start: wrapInNotification((c, names) => c.start(names)),
      VmAction.stop: wrapInNotification((c, names) => c.stop(names)),
      VmAction.restart: wrapInNotification((c, names) => c.restart(names)),
      VmAction.delete: (action) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => DeleteInstanceDialog(
            count: selected.length,
            onDelete: () {
              wrapInNotification((c, names) async {
                await c.purge(names);
                final bindings =
                    ref.read(serviceInstanceBindingsProvider.notifier);
                for (final name in names) {
                  bindings.unbind(name);
                }
              })(action);
              ref
                  .read(selectedServiceInstancesProvider.notifier)
                  .set(BuiltSet());
            },
          ),
        );
      },
      VmAction.forceDelete: (action) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => DeleteInstanceDialog(
            force: true,
            count: selected.length,
            onDelete: () {
              wrapInNotification((c, names) async {
                await c.purge(names);
                final bindings =
                    ref.read(serviceInstanceBindingsProvider.notifier);
                for (final name in names) {
                  bindings.unbind(name);
                }
              })(action);
              ref
                  .read(selectedServiceInstancesProvider.notifier)
                  .set(BuiltSet());
            },
          ),
        );
      },
    };

    return Row(
      children: [
        for (final MapEntry(key: action, value: function) in actions.entries)
          VmActionButton(
            action: action,
            currentStatuses: statuses,
            function: () => function(action),
          ),
      ].gap(width: 8).toList(),
    );
  }
}
