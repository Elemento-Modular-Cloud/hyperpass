import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';

import '../brand.dart';
import '../l10n/app_localizations.dart';
import '../notifications.dart';
import '../overview/recent_activity.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../widgets/launchpad_button.dart';
import 'instances/llm_instances_screen.dart';
import 'llm_features.dart';
import 'providers.dart';

const _inferenceBackendIds = {
  'llamacpp',
  if (enableMlxBackend) 'mlx',
};
const _defaultCtxSize = 8192;
const _defaultMaxTokens = 0;

class _LoadLimits {
  const _LoadLimits({required this.ctxSize, required this.maxTokens});
  final int ctxSize;
  final int maxTokens;
}

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
      barrierColor: Brand.barrier,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.modelsPickRuntimeTitle),
        content: Text(l10n.modelsPickRuntimeBody),
        actions: [
          for (final backend in ready)
            LaunchPadButton.primary(
              onPressed: () => Navigator.pop(ctx, backend.id),
              child: Text(_runtimeLabel(l10n, backend.id, backend.name)),
            ),
          LaunchPadButton.secondary(
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
  final limits = await _promptLoadLimits(context, l10n);
  if (limits == null) return;

  final pending = PendingLlmLoad(
    id: '$pendingLlmLoadIdPrefix${DateTime.now().microsecondsSinceEpoch}',
    modelId: modelId,
    runtime: runtime,
    ctxSize: limits.ctxSize,
    maxTokens: limits.maxTokens,
  );
  ref.read(pendingLlmLoadsProvider.notifier).add(pending);
  ref.read(sidebarKeyProvider.notifier).set(LlmInstancesScreen.sidebarKey);

  unawaited(
    _completeLlmLoad(
      pending: pending,
      modelId: modelId,
      quant: quant,
      hfRepo: hfRepo,
      runtime: runtime,
      ctxSize: limits.ctxSize,
      maxTokens: limits.maxTokens,
    ),
  );
}

Future<void> _completeLlmLoad({
  required PendingLlmLoad pending,
  required String modelId,
  required String quant,
  required String hfRepo,
  required String runtime,
  required int ctxSize,
  required int maxTokens,
}) async {
  try {
    final client = providerContainer.read(grpcClientProvider);
    if (!isModelCachedFromContainer(modelId)) {
      await for (final _ in client.pullModel(
        modelId,
        quant: quant,
        hfRepo: hfRepo,
      )) {}
      providerContainer.invalidate(loadedModelsProvider);
    }
    await client
        .loadModel(
          modelId,
          quant: quant,
          runtime: runtime,
          ctxSize: ctxSize,
          maxTokens: maxTokens,
        )
        .last;
    providerContainer.invalidate(loadedModelsProvider);
    providerContainer.read(recentActivityProvider.notifier).record(
          title: 'Loaded $modelId',
          detail: runtime,
        );
  } catch (e) {
    final message = e is GrpcError ? (e.message ?? '$e') : '$e';
    providerContainer.read(notificationsProvider.notifier).addError(message);
  } finally {
    providerContainer.read(pendingLlmLoadsProvider.notifier).remove(pending.id);
  }
}

Future<_LoadLimits?> _promptLoadLimits(
  BuildContext context,
  AppLocalizations l10n,
) async {
  final ctxController = TextEditingController(text: '$_defaultCtxSize');
  final maxController = TextEditingController(text: '$_defaultMaxTokens');
  final result = await showDialog<_LoadLimits>(
    context: context,
    barrierColor: Brand.barrier,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.modelsLoadLimitsTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.modelsLoadLimitsBody),
          const SizedBox(height: 12),
          TextField(
            controller: ctxController,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.modelsCtxSizeLabel,
              hintText: '$_defaultCtxSize',
              helperText: l10n.modelsCtxSizeHelper,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: maxController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.modelsMaxTokensLabel,
              hintText: '$_defaultMaxTokens',
              helperText: l10n.modelsMaxTokensHelper,
            ),
          ),
        ],
      ),
      actions: [
        LaunchPadButton.secondary(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.commonCancel),
        ),
        LaunchPadButton.primary(
          onPressed: () {
            final ctxSize = int.tryParse(ctxController.text.trim());
            final maxTokens = int.tryParse(maxController.text.trim());
            if (ctxSize == null || ctxSize <= 0 || maxTokens == null || maxTokens < 0) {
              return;
            }
            Navigator.pop(ctx, _LoadLimits(ctxSize: ctxSize, maxTokens: maxTokens));
          },
          child: Text(l10n.modelsLoad),
        ),
      ],
    ),
  );
  ctxController.dispose();
  maxController.dispose();
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

bool isModelCachedFromContainer(String modelId) {
  final cached = providerContainer
          .read(loadedModelsProvider)
          .asData
          ?.value
          .cached ??
      const [];
  return cached.any((m) => m.id == modelId);
}
