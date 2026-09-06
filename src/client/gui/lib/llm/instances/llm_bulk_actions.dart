import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../extensions.dart';
import '../../l10n/app_localizations.dart';
import '../../notifications.dart';
import '../../providers.dart';
import '../providers.dart';
import 'llm_selection.dart';

class LlmBulkActionsBar extends ConsumerWidget {
  const LlmBulkActionsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selected = ref.watch(selectedLlmInstancesProvider);
    final enabled = selected.isNotEmpty;

    return Row(
      children: [
        _BulkTextButton(
          label: l10n.modelsUnload,
          onPressed: enabled
              ? () {
                  final ids = selected.toList(growable: false);
                  final object = ids.length == 1
                      ? ids.first
                      : l10n.bulkActionModelCount(ids.length);
                  ref.read(notificationsProvider.notifier).addOperation(
                        () async {
                          for (final id in ids) {
                            await unloadLlmInstance(id);
                          }
                          providerContainer
                              .read(selectedLlmInstancesProvider.notifier)
                              .set(BuiltSet());
                        }(),
                        loading: l10n.bulkActionMessage(
                          l10n.llmActionUnloadContinuous,
                          object,
                        ),
                        onSuccess: (_) => l10n.bulkActionMessage(
                          l10n.llmActionUnloadPast,
                          object,
                        ),
                        onError: (error) => l10n.bulkActionError(
                          l10n.modelsUnload.toLowerCase(),
                          object,
                          '$error',
                        ),
                      );
                }
              : null,
        ),
      ].gap(width: 8).toList(),
    );
  }
}

class _BulkTextButton extends StatelessWidget {
  const _BulkTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: ButtonStyle(
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: const Color(0xff333333)
                .withAlpha(states.contains(WidgetState.disabled) ? 128 : 255),
          ),
        ),
      ),
      child: Text(label),
    );
  }
}
