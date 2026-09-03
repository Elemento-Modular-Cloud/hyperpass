import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../copyable_text.dart';
import '../../l10n/app_localizations.dart';
import '../../page_surface.dart';
import '../../providers.dart';
import '../llm_id.dart';
import '../providers.dart';

class LlmCredentialsScreen extends ConsumerWidget {
  static const sidebarKey = 'llm-credentials';

  const LlmCredentialsScreen({super.key});

  Future<void> _createKey(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final instances =
        ref.read(loadedModelsProvider).asData?.value.models.toList(growable: false) ??
        const <LoadedModelInfo>[];

    final selectedInstanceId = await showDialog<String?>(
      context: context,
      builder: (ctx) => _CreateKeyDialog(instances: instances),
    );
    if (selectedInstanceId == null || !context.mounted) return;

    try {
      final created = await ref.read(grpcClientProvider).createApiKey(
            label: 'gui',
            instanceId: selectedInstanceId,
          );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.modelsKeyCreatedTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.modelsKeyCreatedBody),
              if (created.instanceId.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  created.openaiId.isNotEmpty
                      ? l10n.modelsKeyBoundInstance(created.openaiId)
                      : created.modelId,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
              const SizedBox(height: 8),
              CopyableText(created.secret),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.modelsClose),
            ),
          ],
        ),
      );
      ref.invalidate(apiKeysProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final keys = ref.watch(apiKeysProvider);
    final hfToken = ref.watch(daemonSettingProvider(llmHfTokenSettingKey));

    return Scaffold(
      body: PageSurface(
        child: ListView(
          children: [
            Text(
              l10n.llmCredentialsLabel,
              style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 24),
            Text(l10n.modelsOpenaiHint, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    '${l10n.modelsBaseUrl}:',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Expanded(child: CopyableText(openaiBaseUrl)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    '${l10n.modelsBaseUrlVm}:',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Expanded(child: CopyableText(openaiVmBaseUrl)),
              ],
            ),
            const SizedBox(height: 24),
            Text(l10n.llmHfTokenLabel, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(l10n.llmHfTokenHint, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            hfToken.when(
              data: (value) => _HfTokenField(initialValue: value),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(l10n.modelsKeysHeading, style: const TextStyle(fontSize: 20)),
                ),
                TextButton(
                  onPressed: () => _createKey(context, ref),
                  child: Text(l10n.modelsCreateKey),
                ),
              ],
            ),
            keys.when(
              data: (reply) {
                if (reply.keys.isEmpty) {
                  return Text(l10n.modelsKeysEmpty);
                }
                return Column(
                  children: [
                    for (final key in reply.keys)
                      ListTile(
                        dense: true,
                        title: Text(key.prefix),
                        subtitle: Text(
                          key.label.isEmpty
                              ? _keyScopeLabel(l10n, key)
                              : '${key.label} · ${_keyScopeLabel(l10n, key)}',
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            try {
                              await ref.read(grpcClientProvider).revokeApiKey(key.id);
                              ref.invalidate(apiKeysProvider);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          },
                          child: Text(l10n.modelsRevokeKey),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
            ),
          ],
        ),
      ),
    );
  }

  String _keyScopeLabel(AppLocalizations l10n, ApiKeyInfo key) {
    if (key.instanceId.isEmpty) {
      return l10n.modelsKeyBoundGlobal;
    }
    final label = key.openaiId.isNotEmpty ? key.openaiId : key.modelId;
    return l10n.modelsKeyBoundInstance(label);
  }
}

class _CreateKeyDialog extends StatefulWidget {
  final List<LoadedModelInfo> instances;

  const _CreateKeyDialog({required this.instances});

  @override
  State<_CreateKeyDialog> createState() => _CreateKeyDialogState();
}

class _CreateKeyDialogState extends State<_CreateKeyDialog> {
  String? _selectedInstanceId;

  String _instanceLabel(LoadedModelInfo model) {
    if (model.openaiId.isNotEmpty) return model.openaiId;
    if (model.modelId.isNotEmpty) return model.modelId;
    return model.instanceId;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasInstances = widget.instances.isNotEmpty;

    return AlertDialog(
      title: Text(l10n.modelsCreateKey),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.modelsKeyScopeLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: _selectedInstanceId,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l10n.modelsKeyScopeGlobal),
              ),
              for (final model in widget.instances)
                DropdownMenuItem<String?>(
                  value: model.instanceId,
                  child: Text(_instanceLabel(model)),
                ),
            ],
            onChanged: (value) => setState(() => _selectedInstanceId = value),
          ),
          if (!hasInstances) ...[
            const SizedBox(height: 8),
            Text(l10n.modelsKeyNoInstances, style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.modelsClose),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selectedInstanceId ?? ''),
          child: Text(l10n.modelsCreateKey),
        ),
      ],
    );
  }
}

class _HfTokenField extends ConsumerStatefulWidget {
  final String initialValue;
  const _HfTokenField({required this.initialValue});

  @override
  ConsumerState<_HfTokenField> createState() => _HfTokenFieldState();
}

class _HfTokenFieldState extends ConsumerState<_HfTokenField> {
  late final TextEditingController _controller;
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(_HfTokenField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(daemonSettingProvider(llmHfTokenSettingKey).notifier).set(_controller.text);
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            obscureText: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _dirty = true),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _dirty ? _save : null,
          child: Text(AppLocalizations.of(context)!.commonSave),
        ),
      ],
    );
  }
}
