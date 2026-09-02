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
                Text('${l10n.modelsBaseUrl}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Expanded(child: CopyableText(openaiBaseUrl)),
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
                  onPressed: () async {
                    try {
                      final created =
                          await ref.read(grpcClientProvider).createApiKey(label: 'gui');
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
                  },
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
                        subtitle: Text(key.label.isEmpty ? key.id : key.label),
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
