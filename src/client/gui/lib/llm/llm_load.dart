import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../sidebar.dart';
import 'instances/llm_instances_screen.dart';
import 'providers.dart';

const _inferenceBackendIds = {'mlx', 'llamacpp'};
const _defaultMaxTokens = 2048;

Future<void> loadLlmModel(
  BuildContext context,
  WidgetRef ref, {
  required String modelId,
  required String quant,
  String hfRepo = '',
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  final backends = await ref.read(llmBackendsProvider.future);
  final ready = backends.backends
      .where((b) => b.status == 'ready' && _inferenceBackendIds.contains(b.id))
      .toList(growable: false);

  if (ready.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.modelsNoRuntimeAvailable)),
    );
    return;
  }

  final String runtime;
  if (ready.length == 1) {
    runtime = ready.first.id;
  } else {
    if (!context.mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.modelsPickRuntimeTitle),
        content: Text(l10n.modelsPickRuntimeBody),
        actions: [
          for (final backend in ready)
            TextButton(
              onPressed: () => Navigator.pop(ctx, backend.id),
              child: Text(_runtimeLabel(l10n, backend.id, backend.name)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
    if (picked == null) return;
    runtime = picked;
  }

  if (!context.mounted) return;
  final maxTokens = await _promptMaxTokens(context, l10n);
  if (maxTokens == null) return;

  try {
    final client = ref.read(grpcClientProvider);
    if (!isModelCached(ref, modelId)) {
      await for (final _ in client.pullModel(modelId, quant: quant, hfRepo: hfRepo)) {}
      ref.invalidate(loadedModelsProvider);
    }
    await client
        .loadModel(modelId, quant: quant, runtime: runtime, maxTokens: maxTokens)
        .last;
    ref.invalidate(loadedModelsProvider);
    ref.read(sidebarKeyProvider.notifier).set(LlmInstancesScreen.sidebarKey);
  } catch (e) {
    final message = e is GrpcError ? (e.message ?? '$e') : '$e';
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<int?> _promptMaxTokens(BuildContext context, AppLocalizations l10n) async {
  final controller = TextEditingController(text: '$_defaultMaxTokens');
  final result = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.modelsMaxTokensTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.modelsMaxTokensBody),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.modelsMaxTokensLabel,
              hintText: '$_defaultMaxTokens',
            ),
            onSubmitted: (_) {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed != null && parsed >= 0) Navigator.pop(ctx, parsed);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed != null && parsed >= 0) Navigator.pop(ctx, parsed);
          },
          child: Text(l10n.modelsLoad),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

String _runtimeLabel(AppLocalizations l10n, String id, String name) {
  if (name.isNotEmpty) return name;
  return switch (id) {
    'mlx' => l10n.modelsRuntimeMlx,
    'llamacpp' => l10n.modelsRuntimeLlama,
    _ => id,
  };
}

bool isModelCached(WidgetRef ref, String modelId) {
  final cached = ref.read(loadedModelsProvider).asData?.value.cached ?? const [];
  return cached.any((m) => m.id == modelId);
}
