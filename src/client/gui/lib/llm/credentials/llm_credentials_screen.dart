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

  Future<void> _addProvider(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_ProviderDraft>(
      context: context,
      barrierColor: Brand.barrier,
      builder: (ctx) => const _ProviderEditorDialog(),
    );
    if (draft == null || !context.mounted) return;
    try {
      final created = await ref.read(grpcClientProvider).createLlmProvider(
            label: draft.label,
            preset: draft.preset,
            baseUrl: draft.baseUrl,
            apiKey: draft.apiKey,
            include: draft.include,
            exclude: draft.exclude,
          );
      ref.invalidate(llmProvidersProvider);
      ref.invalidate(loadedModelsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connected ${created.provider.label} — '
            '${created.provider.modelCount} models exposed. '
            'Prompts to these models leave this machine.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _editProviderFilters(
    BuildContext context,
    WidgetRef ref,
    LlmProviderInfo provider,
  ) async {
    final draft = await showDialog<_ProviderFilterDraft>(
      context: context,
      barrierColor: Brand.barrier,
      builder: (ctx) => _ProviderFilterDialog(provider: provider),
    );
    if (draft == null || !context.mounted) return;
    try {
      await ref.read(grpcClientProvider).updateLlmProvider(
            id: provider.id,
            include: draft.include,
            exclude: draft.exclude,
          );
      ref.invalidate(llmProvidersProvider);
      ref.invalidate(loadedModelsProvider);
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
    final providers = ref.watch(llmProvidersProvider);
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
              title: 'Cloud providers',
              subtitle:
                  'OpenAI-compatible APIs (OpenAI, OpenRouter, Anthropic, custom). '
                  'Models are auto-discovered and exposed on the local OpenAI gateway. '
                  'Prompts leave this machine.',
              trailing: LaunchPadButton.primary(
                onPressed: () => _addProvider(context, ref),
                compact: true,
                child: const Text('Add provider'),
              ),
              child: providers.when(
                data: (reply) {
                  if (reply.providers.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No cloud providers yet. Add OpenAI, OpenRouter, or a custom /v1 endpoint.',
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < reply.providers.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _ProviderCard(
                          provider: reply.providers[i],
                          onRefresh: () async {
                            try {
                              await ref
                                  .read(grpcClientProvider)
                                  .refreshLlmProvider(reply.providers[i].id);
                              ref.invalidate(llmProvidersProvider);
                              ref.invalidate(loadedModelsProvider);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          },
                          onFilters: () => _editProviderFilters(
                            context,
                            ref,
                            reply.providers[i],
                          ),
                          onDelete: () async {
                            try {
                              await ref
                                  .read(grpcClientProvider)
                                  .deleteLlmProvider(reply.providers[i].id);
                              ref.invalidate(llmProvidersProvider);
                              ref.invalidate(loadedModelsProvider);
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
        borderRadius: BorderRadius.circular(Brand.radiusPill),
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
            decoration: const InputDecoration(isDense: true),
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

class _ProviderDraft {
  const _ProviderDraft({
    required this.label,
    required this.preset,
    required this.baseUrl,
    required this.apiKey,
    required this.include,
    required this.exclude,
  });

  final String label;
  final String preset;
  final String baseUrl;
  final String apiKey;
  final List<String> include;
  final List<String> exclude;
}

class _ProviderFilterDraft {
  const _ProviderFilterDraft({
    required this.include,
    required this.exclude,
  });

  final List<String> include;
  final List<String> exclude;
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.onRefresh,
    required this.onFilters,
    required this.onDelete,
  });

  final LlmProviderInfo provider;
  final VoidCallback onRefresh;
  final VoidCallback onFilters;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: onSurface.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  provider.label.isEmpty ? provider.preset : provider.label,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  TextButton(onPressed: onFilters, child: const Text('Filters')),
                  TextButton(onPressed: onRefresh, child: const Text('Refresh')),
                  TextButton(
                    onPressed: onDelete,
                    child: Text(
                      'Remove',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${provider.preset} · ${provider.modelCount} models · key ${provider.keyPrefix}…',
            style: TextStyle(
              fontSize: 12,
              color: onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            provider.baseUrl,
            style: TextStyle(
              fontSize: 12,
              color: onSurface.withValues(alpha: 0.55),
            ),
          ),
          if (provider.include.isNotEmpty || provider.exclude.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (provider.include.isNotEmpty)
                  'include: ${provider.include.join(', ')}',
                if (provider.exclude.isNotEmpty)
                  'exclude: ${provider.exclude.join(', ')}',
              ].join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderEditorDialog extends StatefulWidget {
  const _ProviderEditorDialog();

  @override
  State<_ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<_ProviderEditorDialog> {
  final _label = TextEditingController();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _include = TextEditingController();
  final _exclude = TextEditingController();
  String _preset = 'openrouter';

  static const _presets = <String, String>{
    'openai': 'OpenAI',
    'openrouter': 'OpenRouter',
    'anthropic': 'Anthropic (OpenAI compat)',
    'custom': 'Custom /v1 URL',
  };

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _include.dispose();
    _exclude.dispose();
    super.dispose();
  }

  List<String> _splitGlobs(String raw) => raw
      .split(RegExp(r'[\s,]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add cloud provider'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _preset,
                decoration: const InputDecoration(labelText: 'Preset'),
                items: [
                  for (final e in _presets.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _preset = v ?? 'custom'),
              ),
              TextField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              if (_preset == 'custom')
                TextField(
                  controller: _baseUrl,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://example.com/v1',
                  ),
                ),
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API key'),
              ),
              TextField(
                controller: _include,
                decoration: const InputDecoration(
                  labelText: 'Include globs (optional)',
                  hintText: 'gpt-*, anthropic/*',
                ),
              ),
              TextField(
                controller: _exclude,
                decoration: const InputDecoration(
                  labelText: 'Exclude globs (optional)',
                  hintText: '*-free',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_apiKey.text.trim().isEmpty) return;
            if (_preset == 'custom' && _baseUrl.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _ProviderDraft(
                label: _label.text.trim(),
                preset: _preset,
                baseUrl: _baseUrl.text.trim(),
                apiKey: _apiKey.text.trim(),
                include: _splitGlobs(_include.text),
                exclude: _splitGlobs(_exclude.text),
              ),
            );
          },
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

class _ProviderFilterDialog extends StatefulWidget {
  const _ProviderFilterDialog({required this.provider});

  final LlmProviderInfo provider;

  @override
  State<_ProviderFilterDialog> createState() => _ProviderFilterDialogState();
}

class _ProviderFilterDialogState extends State<_ProviderFilterDialog> {
  late final TextEditingController _include;
  late final TextEditingController _exclude;

  @override
  void initState() {
    super.initState();
    _include = TextEditingController(text: widget.provider.include.join(', '));
    _exclude = TextEditingController(text: widget.provider.exclude.join(', '));
  }

  @override
  void dispose() {
    _include.dispose();
    _exclude.dispose();
    super.dispose();
  }

  List<String> _splitGlobs(String raw) => raw
      .split(RegExp(r'[\s,]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Filters · ${widget.provider.label}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.provider.modelCount} models currently exposed. '
              'Include/exclude globs are applied on the next refresh.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
              ),
            ),
            TextField(
              controller: _include,
              decoration: const InputDecoration(
                labelText: 'Include globs',
                hintText: 'empty = all',
              ),
            ),
            TextField(
              controller: _exclude,
              decoration: const InputDecoration(labelText: 'Exclude globs'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _ProviderFilterDraft(
              include: _splitGlobs(_include.text),
              exclude: _splitGlobs(_exclude.text),
            ),
          ),
          child: const Text('Apply & refresh'),
        ),
      ],
    );
  }
}
