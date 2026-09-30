import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand.dart';
import '../l10n/app_localizations.dart';
import '../layout/compact_layout.dart';
import '../widgets/launchpad_button.dart';
import 'llm_download_form.dart';
import 'llm_features.dart';
import 'providers.dart';

/// Opens the download options dialog, then enqueues one or more pulls.
Future<void> downloadLlmModel(
  BuildContext context,
  WidgetRef ref, {
  required String modelId,
  required String quant,
  String hfRepo = '',
  List<String> supportedRuntimes = const [],
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  final backends = await ref.read(llmBackendsProvider.future);
  final readyIds = backends.backends
      .where((b) => b.status == 'ready' && inferenceBackendIds.contains(b.id))
      .map((b) => b.id)
      .toSet();

  final available = compatibleInferenceRuntimes(
    supportedRuntimes: supportedRuntimes,
  ).where(readyIds.contains).toList(growable: false);

  if (available.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.modelsNoRuntimeAvailable)),
    );
    return;
  }

  final catalogRuntime =
      effectiveCatalogRuntime(ref.read(catalogFiltersProvider).runtime);
  final defaults = <String>{};
  if (catalogRuntime.isNotEmpty && available.contains(catalogRuntime)) {
    defaults.add(catalogRuntime);
  } else if (available.contains('llamacpp')) {
    defaults.add('llamacpp');
  } else {
    defaults.add(available.first);
  }

  if (!context.mounted) return;
  final nameById = {
    for (final b in backends.backends)
      if (b.id.isNotEmpty) b.id: b.name.isEmpty ? b.id : b.name,
  };
  final form = await promptLlmDownloadSettings(
    context,
    l10n,
    availableRuntimes: available
        .map((id) => (id: id, name: nameById[id] ?? id))
        .toList(),
    initial: LlmDownloadForm(runtimes: defaults),
  );
  if (form == null || !form.isValid) return;

  try {
    await ref.read(modelDownloadQueueProvider.notifier).enqueueFromForm(
          modelId: modelId,
          quant: quant,
          hfRepo: hfRepo,
          form: form,
        );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

@visibleForTesting
Future<LlmDownloadForm?> promptLlmDownloadSettings(
  BuildContext context,
  AppLocalizations l10n, {
  required List<({String id, String name})> availableRuntimes,
  required LlmDownloadForm initial,
}) {
  return showDialog<LlmDownloadForm>(
    context: context,
    barrierColor: Brand.barrier,
    builder: (ctx) => _DownloadSettingsDialog(
      l10n: l10n,
      availableRuntimes: availableRuntimes,
      initial: initial,
    ),
  );
}

class _DownloadSettingsDialog extends StatefulWidget {
  const _DownloadSettingsDialog({
    required this.l10n,
    required this.availableRuntimes,
    required this.initial,
  });

  final AppLocalizations l10n;
  final List<({String id, String name})> availableRuntimes;
  final LlmDownloadForm initial;

  @override
  State<_DownloadSettingsDialog> createState() =>
      _DownloadSettingsDialogState();
}

class _DownloadSettingsDialogState extends State<_DownloadSettingsDialog> {
  late LlmDownloadForm form;
  String? error;

  AppLocalizations get l10n => widget.l10n;

  @override
  void initState() {
    super.initState();
    form = widget.initial.copy();
    form.runtimes.removeWhere(
      (id) => !widget.availableRuntimes.any((r) => r.id == id),
    );
    if (form.runtimes.isEmpty && widget.availableRuntimes.isNotEmpty) {
      form.runtimes.add(widget.availableRuntimes.first.id);
    }
  }

  void _commit() {
    if (!form.isValid) {
      setState(() => error = l10n.modelsDownloadSelectRuntime);
      return;
    }
    if (!form.includesLlama) {
      form.quantMode = LlmDownloadQuantMode.recommended;
    }
    Navigator.pop(context, form);
  }

  @override
  Widget build(BuildContext context) {
    final width = CompactLayout.dialogWidth(context, 480);
    return AlertDialog(
      title: Text(l10n.modelsDownloadOptionsTitle),
      constraints: BoxConstraints(minWidth: width, maxWidth: width),
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.modelsDownloadOptionsBody,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.modelsDownloadRuntimesLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...widget.availableRuntimes.map((runtime) {
              final selected = form.runtimes.contains(runtime.id);
              return CheckboxListTile(
                key: Key('llm-download-runtime-${runtime.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(runtime.name.isEmpty ? runtime.id : runtime.name),
                value: selected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      form.runtimes.add(runtime.id);
                    } else {
                      form.runtimes.remove(runtime.id);
                      if (!form.includesLlama) {
                        form.quantMode = LlmDownloadQuantMode.recommended;
                      }
                    }
                    error = null;
                  });
                },
              );
            }),
            const SizedBox(height: 12),
            Text(
              l10n.modelsDownloadQuantLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            RadioListTile<LlmDownloadQuantMode>(
              key: const Key('llm-download-quant-recommended'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.modelsDownloadQuantRecommended),
              value: LlmDownloadQuantMode.recommended,
              groupValue: form.quantMode,
              onChanged: (value) {
                if (value == null) return;
                setState(() => form.quantMode = value);
              },
            ),
            RadioListTile<LlmDownloadQuantMode>(
              key: const Key('llm-download-quant-all'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.modelsDownloadQuantAll),
              value: LlmDownloadQuantMode.allGguf,
              groupValue: form.quantMode,
              onChanged: form.includesLlama
                  ? (value) {
                      if (value == null) return;
                      setState(() => form.quantMode = value);
                    }
                  : null,
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        LaunchPadButton.secondary(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        LaunchPadButton.primary(
          onPressed: _commit,
          child: Text(l10n.modelsDownload),
        ),
      ],
    );
  }
}
