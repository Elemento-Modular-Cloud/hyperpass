import 'package:flutter/material.dart';

import 'confirmation_dialog.dart';
import 'l10n/app_localizations.dart';

class DeleteInstanceDialog extends StatelessWidget {
  final VoidCallback onDelete;
  final int count;
  final bool force;

  const DeleteInstanceDialog({
    super.key,
    required this.onDelete,
    this.count = 1,
    this.force = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ConfirmationDialog(
      title: force
          ? l10n.forceDeleteInstanceTitle(count)
          : l10n.deleteInstanceTitle(count),
      body: Text(
        force
            ? l10n.forceDeleteInstanceBody(count)
            : l10n.deleteInstanceBody(count),
      ),
      actionText: force ? l10n.forceDeleteConfirm : l10n.commonDelete,
      onAction: () {
        onDelete();
        Navigator.pop(context);
      },
      inactionText: l10n.commonCancel,
      onInaction: () => Navigator.pop(context),
    );
  }
}
