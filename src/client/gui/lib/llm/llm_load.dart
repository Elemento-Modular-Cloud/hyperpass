import 'dart:async';

import 'package:flutter/material.dart' hide Switch;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';

import '../brand.dart';
import '../l10n/app_localizations.dart';
import '../layout/compact_layout.dart';
import '../notifications.dart';
import '../overview/recent_activity.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../switch.dart';
import '../widgets/launchpad_button.dart';
import 'instances/llm_instances_screen.dart';
import 'llm_features.dart';
import 'llm_load_form.dart';
import 'llm_load_prefs.dart';
import 'providers.dart';

const _inferenceBackendIds = {
  'llamacpp',
  if (enableMlxBackend) 'mlx',
};

Future<void> loadLlmModel(
  BuildContext context,
  WidgetRef ref, {
  required String modelId,
  required String quant,
  String hfRepo = '',
  int? suggestedCtx,
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

  if (!context.mounted) return;
  final prefs = ref.read(sharedPreferencesProvider);
  final form = await promptLlmLoadSettings(
    context,
    l10n,
    readyRuntimes: ready.map((b) => (id: b.id, name: b.name)).toList(),
    initial: LlmLoadForm.fromJson(
      readLlmLoadPrefs(prefs, modelId),
      suggestedCtx: suggestedCtx,
    ),
  );
  if (form == null) return;

  final pending = PendingLlmLoad(
    id: '$pendingLlmLoadIdPrefix${DateTime.now().microsecondsSinceEpoch}',
    modelId: modelId,
    runtime: form.runtime,
    ctxSize: form.ctxSize,
    maxTokens: form.maxTokens,
  );
  ref.read(pendingLlmLoadsProvider.notifier).add(pending);
  ref.read(sidebarKeyProvider.notifier).set(LlmInstancesScreen.sidebarKey);

  unawaited(
    _completeLlmLoad(
      pending: pending,
      modelId: modelId,
      quant: quant,
      hfRepo: hfRepo,
      form: form,
    ),
  );
}

Future<void> _completeLlmLoad({
  required PendingLlmLoad pending,
  required String modelId,
  required String quant,
  required String hfRepo,
  required LlmLoadForm form,
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
          runtime: form.runtime,
          ctxSize: form.ctxSize,
          maxTokens: form.maxTokens,
          params: form.toProto(),
        )
        .last;
    await writeLlmLoadPrefs(
      providerContainer.read(sharedPreferencesProvider),
      modelId,
      form.toJson(),
    );
    providerContainer.invalidate(loadedModelsProvider);
    providerContainer.read(recentActivityProvider.notifier).record(
          title: 'Loaded $modelId',
          detail: form.runtime,
        );
  } catch (e) {
    final message = e is GrpcError ? (e.message ?? '$e') : '$e';
    providerContainer.read(notificationsProvider.notifier).addError(message);
  } finally {
    providerContainer.read(pendingLlmLoadsProvider.notifier).remove(pending.id);
  }
}

@visibleForTesting
Future<LlmLoadForm?> promptLlmLoadSettings(
  BuildContext context,
  AppLocalizations l10n, {
  required List<({String id, String name})> readyRuntimes,
  required LlmLoadForm initial,
}) {
  return showDialog<LlmLoadForm>(
    context: context,
    barrierColor: Brand.barrier,
    builder: (ctx) => _LoadSettingsDialog(
      l10n: l10n,
      readyRuntimes: readyRuntimes,
      initial: initial,
    ),
  );
}

class _LoadSettingsDialog extends StatefulWidget {
  const _LoadSettingsDialog({
    required this.l10n,
    required this.readyRuntimes,
    required this.initial,
  });

  final AppLocalizations l10n;
  final List<({String id, String name})> readyRuntimes;
  final LlmLoadForm initial;

  @override
  State<_LoadSettingsDialog> createState() => _LoadSettingsDialogState();
}

class _LoadSettingsDialogState extends State<_LoadSettingsDialog> {
  late LlmLoadForm form;
  late final TextEditingController ctxController;
  late final TextEditingController maxController;
  late final TextEditingController customGpuController;
  late final TextEditingController threadsController;
  late final TextEditingController threadsBatchController;
  late final TextEditingController batchController;
  late final TextEditingController ubatchController;
  late final TextEditingController parallelController;
  late final TextEditingController cacheReuseController;
  late final TextEditingController nCpuMoeController;
  String? error;

  AppLocalizations get l10n => widget.l10n;

  @override
  void initState() {
    super.initState();
    form = LlmLoadForm.fromJson(widget.initial.toJson());
    if (widget.readyRuntimes.length == 1) {
      form.runtime = widget.readyRuntimes.first.id;
    } else if (!widget.readyRuntimes.any((r) => r.id == form.runtime)) {
      form.runtime = widget.readyRuntimes.first.id;
    }
    ctxController = TextEditingController(text: '${form.ctxSize}');
    maxController = TextEditingController(text: '${form.maxTokens}');
    customGpuController = TextEditingController(text: '${form.customGpuLayers}');
    threadsController = TextEditingController(text: '${form.threads}');
    threadsBatchController = TextEditingController(text: '${form.threadsBatch}');
    batchController = TextEditingController(text: '${form.batchSize}');
    ubatchController = TextEditingController(text: '${form.ubatchSize}');
    parallelController = TextEditingController(text: '${form.parallel}');
    cacheReuseController = TextEditingController(text: '${form.cacheReuse}');
    nCpuMoeController = TextEditingController(
      text: form.nCpuMoe == null ? '' : '${form.nCpuMoe}',
    );
  }

  @override
  void dispose() {
    ctxController.dispose();
    maxController.dispose();
    customGpuController.dispose();
    threadsController.dispose();
    threadsBatchController.dispose();
    batchController.dispose();
    ubatchController.dispose();
    parallelController.dispose();
    cacheReuseController.dispose();
    nCpuMoeController.dispose();
    super.dispose();
  }

  int _intOr(TextEditingController controller, int fallback) =>
      int.tryParse(controller.text.trim()) ?? fallback;

  void _commit() {
    form.ctxSize = _intOr(ctxController, 0);
    form.maxTokens = _intOr(maxController, -1);
    form.customGpuLayers = _intOr(customGpuController, -1);
    form.threads = _intOr(threadsController, -1);
    form.threadsBatch = _intOr(threadsBatchController, -1);
    form.batchSize = _intOr(batchController, -1);
    form.ubatchSize = _intOr(ubatchController, -1);
    form.parallel = _intOr(parallelController, 0);
    form.cacheReuse = _intOr(cacheReuseController, -1);
    final moe = nCpuMoeController.text.trim();
    form.nCpuMoe = moe.isEmpty ? null : int.tryParse(moe);
    if (!form.isValid) {
      setState(() => error = l10n.modelsLoadSettingsInvalid);
      return;
    }
    Navigator.pop(context, form);
  }

  @override
  Widget build(BuildContext context) {
    final width = CompactLayout.dialogWidth(context, 760);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return AlertDialog(
      title: Text(l10n.modelsLoadLimitsTitle),
      constraints: BoxConstraints(minWidth: width, maxWidth: width),
      content: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.modelsLoadLimitsBody),
                const SizedBox(height: 16),
                _pair(
                  _numberField(
                    key: const Key('llm-load-ctx'),
                    controller: ctxController,
                    label: l10n.modelsCtxSizeLabel,
                    hint: l10n.modelsCtxSizeHelper,
                    autofocus: true,
                  ),
                  _numberField(
                    key: const Key('llm-load-max-tokens'),
                    controller: maxController,
                    label: l10n.modelsMaxTokensLabel,
                    hint: l10n.modelsMaxTokensHelper,
                  ),
                ),
                if (widget.readyRuntimes.length > 1 || form.isLlama) ...[
                  const SizedBox(height: 12),
                  _pair(
                    widget.readyRuntimes.length > 1
                        ? _dropdown(
                            key: const Key('llm-load-runtime'),
                            value: form.runtime,
                            label: l10n.modelsRuntimeLabel,
                            items: [
                              for (final backend in widget.readyRuntimes)
                                (
                                  id: backend.id,
                                  label: _runtimeLabel(l10n, backend.id, backend.name),
                                ),
                            ],
                            onChanged: (value) => setState(() => form.runtime = value),
                          )
                        : form.isLlama
                            ? _gpuOffloadField()
                            : const SizedBox.shrink(),
                    form.isLlama && widget.readyRuntimes.length > 1
                        ? _gpuOffloadField()
                        : form.isLlama && form.gpuOffload == 'custom'
                            ? _customGpuField()
                            : const SizedBox.shrink(),
                  ),
                ],
                if (form.isLlama &&
                    form.gpuOffload == 'custom' &&
                    widget.readyRuntimes.length > 1) ...[
                  const SizedBox(height: 12),
                  _pair(_customGpuField(), const SizedBox.shrink()),
                ],
                if (form.isLlama)
                  ExpansionTile(
                    key: const Key('llm-load-advanced'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                    title: Text(l10n.modelsLoadAdvanced),
                    children: [
                      _pair(
                        _dropdown(
                          value: form.flashAttn,
                          label: l10n.modelsFlashAttnLabel,
                          items: [
                            (id: 'auto', label: l10n.modelsValueAuto),
                            (id: 'on', label: l10n.modelsValueOn),
                            (id: 'off', label: l10n.modelsValueOff),
                          ],
                          onChanged: (value) => setState(() => form.flashAttn = value),
                        ),
                        _dropdown(
                          value: form.cacheType,
                          label: l10n.modelsKvCacheLabel,
                          items: const [
                            (id: 'q8_0', label: 'q8_0'),
                            (id: 'q4_0', label: 'q4_0'),
                            (id: 'f16', label: 'f16'),
                          ],
                          onChanged: (value) => setState(() => form.cacheType = value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pair(
                        Switch(
                          trailingSwitch: true,
                          value: form.fit,
                          label: l10n.modelsFitLabel,
                          onChanged: (value) => setState(() => form.fit = value),
                        ),
                        Switch(
                          trailingSwitch: true,
                          value: form.keepInRam,
                          label: l10n.modelsKeepInRamLabel,
                          onChanged: (value) =>
                              setState(() => form.keepInRam = value),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _pair(
                        _numberField(
                          controller: threadsController,
                          label: l10n.modelsThreadsLabel,
                          hint: l10n.modelsThreadsHelper,
                        ),
                        _numberField(
                          controller: threadsBatchController,
                          label: l10n.modelsThreadsBatchLabel,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pair(
                        _numberField(
                          controller: batchController,
                          label: l10n.modelsBatchSizeLabel,
                        ),
                        _numberField(
                          controller: ubatchController,
                          label: l10n.modelsUbatchSizeLabel,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pair(
                        _numberField(
                          controller: parallelController,
                          label: l10n.modelsParallelLabel,
                        ),
                        _numberField(
                          controller: cacheReuseController,
                          label: l10n.modelsCacheReuseLabel,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _pair(
                        _dropdown(
                          value: form.moeOffload,
                          label: l10n.modelsMoeOffloadLabel,
                          items: [
                            (id: 'auto', label: l10n.modelsValueAuto),
                            (id: 'cpu', label: l10n.modelsMoeOffloadCpu),
                            (id: 'off', label: l10n.modelsValueOff),
                          ],
                          onChanged: (value) => setState(() => form.moeOffload = value),
                        ),
                        _numberField(
                          controller: nCpuMoeController,
                          label: l10n.modelsNCpuMoeLabel,
                          requiredDigits: false,
                        ),
                      ),
                    ],
                  ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        LaunchPadButton.secondary(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        LaunchPadButton.primary(
          onPressed: _commit,
          child: Text(l10n.modelsLoad),
        ),
      ],
    );
  }

  Widget _gpuOffloadField() {
    return _dropdown(
      key: const Key('llm-load-gpu'),
      value: form.gpuOffload,
      label: l10n.modelsGpuOffloadLabel,
      items: [
        (id: 'auto', label: l10n.modelsGpuOffloadAuto),
        (id: 'all', label: l10n.modelsGpuOffloadAll),
        (id: 'cpu', label: l10n.modelsGpuOffloadCpu),
        (id: 'custom', label: l10n.modelsGpuOffloadCustom),
      ],
      onChanged: (value) => setState(() => form.gpuOffload = value),
    );
  }

  Widget _customGpuField() {
    return _numberField(
      key: const Key('llm-load-gpu-custom'),
      controller: customGpuController,
      label: l10n.modelsGpuLayersLabel,
    );
  }

  Widget _pair(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }

  Widget _labeled({
    required String label,
    required Widget field,
    String? hint,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final title = Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: onSurface.withValues(alpha: 0.72),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hint == null)
          title
        else
          Tooltip(
            message: hint,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: title),
                const SizedBox(width: 4),
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: onSurface.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  Widget _dropdown({
    Key? key,
    required String value,
    required String label,
    required List<({String id, String label})> items,
    required ValueChanged<String> onChanged,
  }) {
    return _labeled(
      label: label,
      field: DropdownButtonFormField<String>(
        key: key,
        value: value,
        isExpanded: true,
        borderRadius: BorderRadius.circular(Brand.radius),
        icon: const Icon(Icons.keyboard_arrow_down, size: 20),
        decoration: const InputDecoration(isDense: true),
        items: [
          for (final item in items)
            DropdownMenuItem(value: item.id, child: Text(item.label)),
        ],
        onChanged: (next) {
          if (next == null) return;
          onChanged(next);
        },
      ),
    );
  }

  Widget _numberField({
    Key? key,
    required TextEditingController controller,
    required String label,
    String? hint,
    bool autofocus = false,
    bool requiredDigits = true,
  }) {
    return _labeled(
      label: label,
      hint: hint,
      field: TextField(
        key: key,
        controller: controller,
        autofocus: autofocus,
        keyboardType: TextInputType.number,
        inputFormatters: [
          if (requiredDigits) FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: const InputDecoration(isDense: true),
      ),
    );
  }
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

int? suggestedCtxForModel({int usableContext = 0, int contextLength = 0}) {
  if (usableContext > 0) return usableContext;
  if (contextLength > 0) return contextLength;
  return null;
}
