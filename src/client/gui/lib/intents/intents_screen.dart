import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../confirmation_dialog.dart';
import '../l10n/app_localizations.dart';
import '../layout/compact_layout.dart';
import '../llm/llm_id.dart';
import '../page_surface.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../vm_details/vm_status_icon.dart';
import '../widgets/launchpad_button.dart';

/// A named group of instances launched together (e.g. "test-app-1" = redis +
/// postgres). Backed by the daemon's own intent registry (`elp intent
/// create/add/list/info/delete`); this screen is a GUI front-end for the
/// same registry, not a separate concept.
class IntentsScreen extends ConsumerWidget {
  static const sidebarKey = 'intents';

  const IntentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intentsAsync = ref.watch(intentsStreamProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Intents',
                    style: TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
                  ),
                ),
                IconButton(
                  tooltip: l10n.catalogueRefresh,
                  onPressed: () => ref.invalidate(intentsStreamProvider),
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                LaunchPadButton.primary(
                  onPressed: () => showCreateIntentDialog(context, ref),
                  child: const Text('New intent'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Named groups of instances launched together, e.g. a "redis" and '
              'a "postgres" instance for the same app.',
              style: TextStyle(fontSize: 14, color: onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: intentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('$error')),
                data: (intents) => intents.isEmpty
                    ? Center(
                        child: Text(
                          'No intents yet. Create one to launch instances as a '
                          'named group.',
                          style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: intents.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            _IntentCard(intent: intents[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntentCard extends ConsumerWidget {
  const _IntentCard({required this.intent});

  final IntentInfo intent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: onSurface.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    intent.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add member',
                  icon: const Icon(Icons.add),
                  onPressed: () => showAddMemberDialog(context, ref, intent.name),
                ),
                IconButton(
                  tooltip: 'Delete intent',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => showDeleteIntentDialog(context, ref, intent.name),
                ),
              ],
            ),
            if (intent.members.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'No members yet.',
                  style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
                ),
              )
            else
              ...intent.members.map((member) {
                final isLlm = member.kind == 'llm';
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InkWell(
                    onTap: () => ref.read(sidebarKeyProvider.notifier).set(
                          isLlm
                              ? LlmInstanceId(
                                  instanceId: member.instanceName,
                                  modelId: '',
                                ).sidebarKey
                              : elpVm(member.instanceName).sidebarKey,
                        ),
                    child: Row(
                      children: [
                        VmStatusIcon(
                          member.instanceStatus.status,
                          isLaunching: false,
                        ),
                        const SizedBox(width: 12),
                        Text(member.role,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        Text(
                          isLlm ? '(LLM: ${member.instanceName})' : '(${member.instanceName})',
                          style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _MemberFields {
  _MemberFields()
      : roleController = TextEditingController(),
        imageController = TextEditingController(),
        modelIdController = TextEditingController();

  final TextEditingController roleController;
  final TextEditingController imageController;
  // When set, this member is an LLM session (loaded the same as `elp llm
  // load`) instead of a VM instance; imageController is then ignored.
  final TextEditingController modelIdController;

  void dispose() {
    roleController.dispose();
    imageController.dispose();
    modelIdController.dispose();
  }

  IntentMemberRequest? toRequest() {
    final role = roleController.text.trim();
    if (role.isEmpty) return null;
    final modelId = modelIdController.text.trim();
    if (modelId.isNotEmpty)
      return IntentMemberRequest(role: role, modelId: modelId);
    return IntentMemberRequest(
      role: role,
      image: imageController.text.trim(),
    );
  }
}

Widget _memberFieldsRow(
  _MemberFields fields, {
  VoidCallback? onRemove,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: fields.roleController,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  hintText: 'e.g. redis',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: fields.imageController,
                decoration: const InputDecoration(
                  labelText: 'Image (optional)',
                  hintText: 'blank = use "redis"/"postgres" template',
                ),
              ),
            ),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextFormField(
            controller: fields.modelIdController,
            decoration: const InputDecoration(
              labelText: 'Model ID (optional, for an LLM member)',
              hintText: 'e.g. llama-3.1-8b-instruct; ignores Image above when set',
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> showCreateIntentDialog(BuildContext context, WidgetRef ref) async {
  final nameController = TextEditingController();
  // Starts empty: an intent can be created with no members at all and
  // populated later via "Add member".
  final members = <_MemberFields>[];
  String? error;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        shape: const Border(),
        title: const Text('New intent'),
        content: SizedBox(
          width: CompactLayout.dialogWidth(dialogContext, 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Intent name',
                    hintText: 'e.g. test-app-1',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Members (optional)', style: TextStyle(fontWeight: FontWeight.w500)),
                const Text(
                  'Add now, or leave empty and add members later.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                for (final member in members)
                  _memberFieldsRow(
                    member,
                    onRemove: () => setDialogState(() => members.remove(member)),
                  ),
                TextButton.icon(
                  onPressed: () =>
                      setDialogState(() => members.add(_MemberFields())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add a member'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style:
                          TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          LaunchPadButton.primary(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                setDialogState(() => error = 'Please provide an intent name.');
                return;
              }
              final requests = members.map((m) => m.toRequest()).toList();
              if (requests.any((r) => r == null)) {
                setDialogState(() => error = 'Every member needs a role.');
                return;
              }

              try {
                await ref.read(grpcClientProvider).intentCreate(
                      IntentCreateRequest(
                        name: name,
                        members: requests.whereType<IntentMemberRequest>(),
                      ),
                    );
                ref.invalidate(intentsStreamProvider);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) setDialogState(() => error = '$e');
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );

  nameController.dispose();
  for (final member in members) {
    member.dispose();
  }
}

Future<void> showAddMemberDialog(
  BuildContext context,
  WidgetRef ref,
  String intentName,
) async {
  final member = _MemberFields();
  String? error;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        shape: const Border(),
        title: Text('Add member to $intentName'),
        content: SizedBox(
          width: CompactLayout.dialogWidth(dialogContext, 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _memberFieldsRow(member),
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
              final request = member.toRequest();
              if (request == null) {
                setDialogState(() => error = 'Please provide a role.');
                return;
              }
              try {
                await ref.read(grpcClientProvider).intentAddMember(
                      IntentAddMemberRequest(name: intentName, members: [request]),
                    );
                ref.invalidate(intentsStreamProvider);
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

  member.dispose();
}

Future<void> showDeleteIntentDialog(
  BuildContext context,
  WidgetRef ref,
  String intentName,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => ConfirmationDialog(
      title: 'Delete intent',
      body: Text(
        'Delete "$intentName"? Its member instances will be deleted too.',
      ),
      actionText: 'Delete',
      onAction: () => Navigator.pop(dialogContext, true),
      inactionText: 'Cancel',
      onInaction: () => Navigator.pop(dialogContext, false),
    ),
  );
  if (confirmed != true) return;

  try {
    await ref.read(grpcClientProvider).intentDelete(intentName, purge: true);
    ref.invalidate(intentsStreamProvider);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}
