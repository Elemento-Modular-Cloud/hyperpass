import 'package:collection/collection.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../confirmation_dialog.dart';
import '../layout/compact_layout.dart';
import '../notifications.dart';
import '../page_surface.dart';
import '../providers.dart';
import '../widgets/launchpad_button.dart';

/// Manages the "known hosts" list migration targets can be picked from (see
/// Daemon::list_network_hosts) — hosts discovered on the network via mDNS need no entry
/// here at all, this is only for the manually-added fallback (a different subnet/VLAN,
/// or mDNS just not being reachable).
class HostsScreen extends ConsumerWidget {
  static const sidebarKey = 'hosts';

  const HostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostsAsync = ref.watch(networkHostsStreamProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Migration Hosts',
                    style: TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => ref.invalidate(networkHostsStreamProvider),
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                LaunchPadButton.primary(
                  onPressed: () => showAddHostDialog(context, ref),
                  child: const Text('Add host'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Targets for "Migrate" (see an instance or intent\'s own menu). Hosts on the '
              'same network are found automatically; add one by hand if it\'s on a '
              'different network or isn\'t found.',
              style: TextStyle(fontSize: 14, color: onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: hostsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('$error')),
                data: (hosts) => hosts.isEmpty
                    ? Center(
                        child: Text(
                          'No hosts yet. Add one to migrate instances there.',
                          style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: hosts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _HostCard(host: hosts[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HostCard extends ConsumerWidget {
  const _HostCard({required this.host});

  final NetworkHost host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final subtitle = [
      if (host.hostOs.isNotEmpty) host.hostOs,
      if (host.hostArch.isNotEmpty) host.hostArch,
      if (host.backend.isNotEmpty) host.backend,
      if (host.address.isNotEmpty) host.address,
    ].join(' · ');

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: onSurface.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              host.discovered ? Icons.wifi_tethering : Icons.dns_outlined,
              color: onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(host.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: TextStyle(color: onSurface.withValues(alpha: 0.6))),
                  if (host.target.isNotEmpty)
                    Text(host.target, style: TextStyle(color: onSurface.withValues(alpha: 0.6))),
                ],
              ),
            ),
            Text(
              host.discovered ? 'On network' : 'Known host',
              style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.5)),
            ),
            if (!host.discovered) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => showRemoveHostDialog(context, ref, host.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A text field for an ssh identity (private key) file, with a "Browse..." button opening the
/// native file picker (no fixed extension — private keys are commonly extensionless, e.g.
/// id_ed25519) as the closest fit to "autocompletion" for a filesystem path in a Flutter
/// desktop app; the OS's own file dialog already gives path-typing/autocomplete besides.
Widget _identityFileField(
  TextEditingController controller,
  void Function(void Function()) setDialogState,
) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'SSH identity file (optional)',
            hintText: '~/.ssh/id_ed25519',
            helperText: 'Leave blank to use ssh\'s own default identity.',
          ),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: IconButton(
          tooltip: 'Browse...',
          icon: const Icon(Icons.folder_open),
          onPressed: () async {
            final file = await openFile();
            if (file == null) return;
            setDialogState(() => controller.text = file.path);
          },
        ),
      ),
    ],
  );
}

Future<void> showAddHostDialog(BuildContext context, WidgetRef ref) async {
  final labelController = TextEditingController();
  final targetController = TextEditingController();
  final identityController = TextEditingController();
  String? error;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        shape: const Border(),
        title: const Text('Add migration host'),
        content: SizedBox(
          width: CompactLayout.dialogWidth(dialogContext, 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: labelController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'e.g. office-desktop',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: targetController,
                decoration: const InputDecoration(
                  labelText: 'Target',
                  hintText: 'user@host',
                ),
              ),
              const SizedBox(height: 12),
              _identityFileField(identityController, setDialogState),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          LaunchPadButton.primary(
            onPressed: () async {
              final label = labelController.text.trim();
              final target = targetController.text.trim();
              if (label.isEmpty) {
                setDialogState(() => error = 'Please provide a label.');
                return;
              }
              if (!target.contains('@')) {
                setDialogState(() => error = 'Target must be in "user@host" form.');
                return;
              }
              try {
                await ref.read(grpcClientProvider).addKnownHost(
                      label,
                      target,
                      identityFile: identityController.text.trim(),
                    );
                ref.invalidate(networkHostsStreamProvider);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) setDialogState(() => error = '$e');
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );

  labelController.dispose();
  targetController.dispose();
  identityController.dispose();
}

Future<void> showRemoveHostDialog(
  BuildContext context,
  WidgetRef ref,
  String label,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => ConfirmationDialog(
      title: 'Remove host',
      body: Text('Remove "$label" from the migration host list?'),
      actionText: 'Remove',
      onAction: () => Navigator.pop(dialogContext, true),
      inactionText: 'Cancel',
      onInaction: () => Navigator.pop(dialogContext, false),
    ),
  );
  if (confirmed != true) return;

  try {
    await ref.read(grpcClientProvider).removeKnownHost(label);
    ref.invalidate(networkHostsStreamProvider);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// Dialog used from an instance's or intent's own menu to migrate it elsewhere: pick a
/// discovered/known host (or type a brand new "user@host"), optionally keep the source.
Future<void> showMigrateDialog(
  BuildContext context,
  WidgetRef ref, {
  required String name,
}) async {
  String? selectedLabel;
  final customTargetController = TextEditingController();
  final usernameController = TextEditingController();
  final identityController = TextEditingController();
  var copy = false;
  String? error;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => Consumer(
        builder: (dialogContext, ref, _) {
          final hosts = ref.watch(networkHostsStreamProvider).asData?.value ?? const [];
          final selected = selectedLabel == null
              ? null
              : hosts.firstWhereOrNull((h) => h.label == selectedLabel);
          final needsUsername = selected != null && selected.target.isEmpty;

          return AlertDialog(
            shape: const Border(),
            title: Text('Migrate "$name"'),
            content: SizedBox(
              width: CompactLayout.dialogWidth(dialogContext, 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: selectedLabel,
                    decoration: const InputDecoration(labelText: 'Target host'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Type a new host...')),
                      for (final host in hosts)
                        DropdownMenuItem(value: host.label, child: Text(host.label)),
                    ],
                    onChanged: (value) => setDialogState(() {
                      selectedLabel = value;
                      error = null;
                      // Pre-fill from the newly-selected host's own saved default (still
                      // editable afterward, e.g. to override for just this migration).
                      final newlySelected =
                          value == null ? null : hosts.firstWhereOrNull((h) => h.label == value);
                      identityController.text = newlySelected?.identityFile ?? '';
                    }),
                  ),
                  if (selected == null) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: customTargetController,
                      decoration: const InputDecoration(
                        labelText: 'Target',
                        hintText: 'user@host',
                      ),
                    ),
                  ] else if (needsUsername) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText: 'SSH username on ${selected.address.isNotEmpty ? selected.address : selected.hostName}',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _identityFileField(identityController, setDialogState),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Keep the source instead of deleting it'),
                    value: copy,
                    onChanged: (value) => setDialogState(() => copy = value ?? false),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              LaunchPadButton.primary(
                onPressed: () {
                  final String target;
                  if (selected == null) {
                    target = customTargetController.text.trim();
                  } else if (!needsUsername) {
                    target = selected.target;
                  } else {
                    final username = usernameController.text.trim();
                    final address =
                        selected.address.isNotEmpty ? selected.address : selected.hostName;
                    target = username.isEmpty ? '' : '$username@$address';
                  }
                  if (!target.contains('@')) {
                    setDialogState(() => error = 'Please provide a valid "user@host" target.');
                    return;
                  }

                  Navigator.pop(dialogContext);
                  final op = ref.read(grpcClientProvider).migrate(
                        name,
                        target,
                        copy: copy,
                        identityFile: identityController.text.trim(),
                      );
                  ref.read(notificationsProvider.notifier).addOperation(
                        op,
                        loading: 'Migrating "$name" to $target...',
                        onSuccess: (reply) {
                          final message = reply?.replyMessage;
                          return message?.isNotEmpty == true
                              ? message!
                              : 'Migrated "$name" to $target';
                        },
                        onError: (e) => '$e',
                      );
                  op.whenComplete(() {
                    ref.invalidate(intentsStreamProvider);
                  });
                },
                child: const Text('Migrate'),
              ),
            ],
          );
        },
      ),
    ),
  );

  customTargetController.dispose();
  usernameController.dispose();
  identityController.dispose();
}
