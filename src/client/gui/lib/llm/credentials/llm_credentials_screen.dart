import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brand.dart';
import '../../catalogue/catalogue_surface.dart';
import '../../copyable_text.dart';
import '../../l10n/app_localizations.dart';
import '../../layout/compact_layout.dart';
import '../../page_surface.dart';
import '../../widgets/launchpad_button.dart';
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

    final draft = await showDialog<_KeyDraft>(
      context: context,
      barrierColor: Brand.barrier,
      builder: (ctx) => _KeyEditorDialog(
        title: l10n.modelsCreateKey,
        confirmLabel: l10n.modelsCreateKey,
        instances: instances,
        initial: const _KeyDraft(label: 'gui', instanceIds: []),
      ),
    );
    if (draft == null || !context.mounted) return;

    try {
      final created = await ref.read(grpcClientProvider).createApiKey(
            label: draft.label.trim().isEmpty ? 'gui' : draft.label.trim(),
            instanceIds: draft.instanceIds,
          );
      if (!context.mounted) return;
      await showDialog<void>(
      context: context,
      barrierColor: Brand.barrier,
      builder: (ctx) => AlertDialog(
          title: Text(l10n.modelsKeyCreatedTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.modelsKeyCreatedBody),
              const SizedBox(height: 12),
              Text(
                _scopeSummary(l10n, created.instanceIds, instances),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
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

  Future<void> _editKey(
    BuildContext context,
    WidgetRef ref,
    ApiKeyInfo key,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final instances =
        ref.read(loadedModelsProvider).asData?.value.models.toList(growable: false) ??
            const <LoadedModelInfo>[];

    final draft = await showDialog<_KeyDraft>(
      context: context,
      barrierColor: Brand.barrier,
      builder: (ctx) => _KeyEditorDialog(
        title: l10n.modelsKeyEditTitle,
        confirmLabel: l10n.commonSave,
        instances: instances,
        initial: _KeyDraft(
          label: key.label,
          instanceIds: _keyInstanceIds(key),
        ),
      ),
    );
    if (draft == null || !context.mounted) return;

    try {
      await ref.read(grpcClientProvider).updateApiKey(
            id: key.id,
            label: draft.label.trim(),
            instanceIds: draft.instanceIds,
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
    final instances =
        ref.watch(loadedModelsProvider).asData?.value.models.toList(growable: false) ??
            const <LoadedModelInfo>[];
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      body: PageSurface(
        child: ListView(
          children: [
            Text(
              l10n.llmCredentialsLabel,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 37,
                fontWeight: FontWeight.w300,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.modelsCredentialsIntro,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 14,
                height: 1.4,
                color: onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 24),
            _SectionCard(
              title: l10n.modelsGatewayHeading,
              subtitle: l10n.modelsOpenaiHint,
              child: Column(
                children: [
                  _EndpointRow(
                    label: l10n.modelsBaseUrl,
                    value: openaiBaseUrl,
                  ),
                  const SizedBox(height: 10),
                  _EndpointRow(
                    label: l10n.modelsBaseUrlVm,
                    value: openaiVmBaseUrl,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: l10n.llmHfTokenLabel,
              subtitle: l10n.llmHfTokenHint,
              child: hfToken.when(
                data: (value) => _HfTokenField(initialValue: value),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: l10n.modelsKeysHeading,
              subtitle: l10n.modelsKeysIntro,
              trailing: LaunchPadButton.primary(
                onPressed: () => _createKey(context, ref),
                compact: true,
                child: Text(l10n.modelsCreateKey),
              ),
              child: keys.when(
                data: (reply) {
                  if (reply.keys.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        l10n.modelsKeysEmpty,
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < reply.keys.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _ApiKeyCard(
                          keyInfo: reply.keys[i],
                          instances: instances,
                          onEdit: () => _editKey(context, ref, reply.keys[i]),
                          onRevoke: () async {
                            try {
                              await ref
                                  .read(grpcClientProvider)
                                  .revokeApiKey(reply.keys[i].id);
                              ref.invalidate(apiKeysProvider);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          },
                        ),
                      ],
                    ],
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _keyInstanceIds(ApiKeyInfo key) {
  if (key.instanceIds.isNotEmpty) return List<String>.from(key.instanceIds);
  if (key.instanceId.isNotEmpty) return [key.instanceId];
  return const [];
}

String _instanceLabel(LoadedModelInfo model) {
  if (model.openaiId.isNotEmpty) return model.openaiId;
  if (model.modelId.isNotEmpty) return model.modelId;
  return model.instanceId;
}

String _scopeSummary(
  AppLocalizations l10n,
  Iterable<String> instanceIds,
  List<LoadedModelInfo> instances,
) {
  final ids = instanceIds.where((id) => id.isNotEmpty).toList(growable: false);
  if (ids.isEmpty) return l10n.modelsKeyBoundGlobal;
  final labels = <String>[];
  for (final id in ids) {
    final match = instances.where((m) => m.instanceId == id).firstOrNull;
    labels.add(match == null ? id : _instanceLabel(match));
  }
  if (labels.length == 1) {
    return l10n.modelsKeyBoundInstance(labels.first);
  }
  return l10n.modelsKeyBoundCount(labels.length);
}

class _KeyDraft {
  const _KeyDraft({required this.label, required this.instanceIds});

  final String label;
  final List<String> instanceIds;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return CatalogueSurface(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: Brand.fontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: Brand.fontFamily,
                        fontSize: 13,
                        height: 1.35,
                        color: onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        Expanded(child: CopyableText(value)),
      ],
    );
  }
}

class _ApiKeyCard extends StatelessWidget {
  const _ApiKeyCard({
    required this.keyInfo,
    required this.instances,
    required this.onEdit,
    required this.onRevoke,
  });

  final ApiKeyInfo keyInfo;
  final List<LoadedModelInfo> instances;
  final VoidCallback onEdit;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final ids = _keyInstanceIds(keyInfo);
    final isGlobal = ids.isEmpty;
    final labels = <String>[];
    for (final id in ids) {
      final match = instances.where((m) => m.instanceId == id).firstOrNull;
      labels.add(match == null ? id : _instanceLabel(match));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        keyInfo.prefix,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        keyInfo.label.isEmpty
                            ? l10n.modelsKeyUntitled
                            : keyInfo.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                LaunchPadButton.secondary(
                  onPressed: onEdit,
                  compact: true,
                  child: Text(l10n.modelsKeyEditAccess),
                ),
                LaunchPadButton.destructive(
                  onPressed: onRevoke,
                  compact: true,
                  child: Text(l10n.modelsRevokeKey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ScopeChip(
                  label: isGlobal
                      ? l10n.modelsKeyBoundGlobal
                      : l10n.modelsKeyBoundCount(labels.length),
                  emphasized: true,
                ),
                if (!isGlobal)
                  for (final label in labels) _ScopeChip(label: label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label, this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: emphasized ? Brand.primaryMuted : onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasized
              ? Brand.primary.withValues(alpha: 0.45)
              : onSurface.withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
          color: emphasized ? Brand.primary : onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _KeyEditorDialog extends StatefulWidget {
  const _KeyEditorDialog({
    required this.title,
    required this.confirmLabel,
    required this.instances,
    required this.initial,
  });

  final String title;
  final String confirmLabel;
  final List<LoadedModelInfo> instances;
  final _KeyDraft initial;

  @override
  State<_KeyEditorDialog> createState() => _KeyEditorDialogState();
}

class _KeyEditorDialogState extends State<_KeyEditorDialog> {
  late final TextEditingController _label;
  late bool _global;
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.initial.label);
    _global = widget.initial.instanceIds.isEmpty;
    _selected = {...widget.initial.instanceIds};
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  bool get _canSave {
    if (_global) return true;
    return _selected.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasInstances = widget.instances.isNotEmpty;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: CompactLayout.dialogWidth(context, 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.modelsKeyLabelField,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _label,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: l10n.modelsKeyLabelHint,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.modelsKeyScopeLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.modelsKeyScopeHelp,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 8),
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.modelsKeyScopeGlobal),
              subtitle: Text(l10n.modelsKeyScopeGlobalHint),
              value: true,
              groupValue: _global,
              onChanged: (_) => setState(() => _global = true),
            ),
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.modelsKeyScopeSpecific),
              subtitle: Text(
                hasInstances || _selected.isNotEmpty
                    ? l10n.modelsKeyScopeSpecificHint
                    : l10n.modelsKeyNoInstances,
              ),
              value: false,
              groupValue: _global,
              onChanged: (hasInstances || _selected.isNotEmpty)
                  ? (_) => setState(() => _global = false)
                  : null,
            ),
            if (!_global && (hasInstances || _selected.isNotEmpty)) ...[
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final model in widget.instances)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _selected.contains(model.instanceId),
                        title: Text(_instanceLabel(model)),
                        subtitle: Text(
                          model.backend.isEmpty ? model.instanceId : model.backend,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selected.add(model.instanceId);
                            } else {
                              _selected.remove(model.instanceId);
                            }
                          });
                        },
                      ),
                    for (final orphan in _selected.where(
                      (id) =>
                          !widget.instances.any((m) => m.instanceId == id),
                    ))
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: true,
                        title: Text(orphan),
                        subtitle: Text(
                          l10n.modelsKeyOrphanHint,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onChanged: (checked) {
                          setState(() {
                            if (checked != true) _selected.remove(orphan);
                          });
                        },
                      ),
                  ],
                ),
              ),
              if (!_canSave)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.modelsKeySelectOne,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
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
          onPressed: !_canSave
              ? null
              : () => Navigator.pop(
                    context,
                    _KeyDraft(
                      label: _label.text,
                      instanceIds: _global ? const [] : _selected.toList(),
                    ),
                  ),
          child: Text(widget.confirmLabel),
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
    await ref
        .read(daemonSettingProvider(llmHfTokenSettingKey).notifier)
        .set(_controller.text);
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
        LaunchPadButton.primary(
          onPressed: _dirty ? _save : null,
          compact: true,
          child: Text(AppLocalizations.of(context)!.commonSave),
        ),
      ],
    );
  }
}
