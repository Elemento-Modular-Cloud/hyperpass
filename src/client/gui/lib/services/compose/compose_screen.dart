import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/feature_access.dart';
import '../../auth/feature_lock.dart';
import '../../brand.dart';
import '../../catalogue/catalogue.dart';
import '../../catalogue/catalogue_entry.dart';
import '../../catalogue/launch_form.dart';
import '../../distro_branding.dart';
import '../../intents/intents_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../layout/compact_layout.dart';
import '../../llm/catalogue/model_branding.dart';
import '../../llm/llm_load.dart';
import '../../llm/llm_load_form.dart';
import '../../llm/llm_load_prefs.dart';
import '../../llm/providers.dart';
import '../../page_surface.dart';
import '../../providers.dart';
import '../../sidebar.dart';
import '../../widgets/launchpad_button.dart';
import '../service_branding.dart';
import '../service_library.dart';
import 'compose_canvas.dart';
import 'compose_graph.dart';
import 'compose_run.dart';
import 'compose_store.dart';
import 'compose_style.dart';

Future<void> ensureNamedComposeIntent(WidgetRef ref, String name) async {
  if (!ref.read(daemonAvailableProvider)) return;
  await ensureComposeIntent(
    daemonAvailable: true,
    intents: ref.read(intentsStreamProvider).asData?.value ?? const [],
    grpc: ref.read(grpcClientProvider),
    name: name,
    invalidateIntents: () => ref.invalidate(intentsStreamProvider),
  );
}

class ComposeScreen extends ConsumerWidget {
  static const sidebarKey = 'service-compose';

  const ComposeScreen({this.embedded = false, super.key});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final libraryAsync = ref.watch(marketplaceLibraryProvider);
    final editor = ref.watch(composeEditorProvider);
    final progress = ref.watch(composeDeployProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hasIntent = editor.graph.intentName.trim().isNotEmpty;

    final body = libraryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(l10n.servicesLoadError('$error'))),
      data: (library) {
        final issues = validateComposeGraph(editor.graph, library);
        final deploying = progress?.running == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!embedded) ...[
              Text(
                l10n.composeLabel,
                style: const TextStyle(
                  fontSize: 37,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              l10n.composeSubtitle,
              style: TextStyle(
                fontSize: 14,
                color: onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
                  child: const _IntentPicker(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        LaunchPadButton.secondary(
                          onPressed: deploying
                              ? null
                              : () => showNewComposeIntentDialog(context, ref),
                          child: Text(l10n.composeNewIntent),
                        ),
                        LaunchPadButton.secondary(
                          onPressed: deploying || !hasIntent
                              ? null
                              : () => _save(context, ref),
                          child: Text(l10n.composeSave),
                        ),
                        LaunchPadButton.primary(
                          onPressed: deploying || issues.isNotEmpty
                              ? null
                              : () =>
                                  _deploy(context, ref, library, editor.graph),
                          child: Text(
                            deploying
                                ? (progress?.message ?? l10n.composeDeploying)
                                : l10n.composeDeployAction,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (progress?.error != null) ...[
              const SizedBox(height: 8),
              Text(
                progress!.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                issues.first.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 240,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: onSurface.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        child: _ComposePalette(library: library),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: ComposeCanvas(library: library)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 280,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: onSurface.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _ComposeInspector(library: library),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (embedded) return body;
    return Scaffold(body: PageSurface(child: body));
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final name = ref.read(composeEditorProvider).graph.intentName.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.composeNeedIntent)),
      );
      return;
    }
    ref.read(composeEditorProvider.notifier).save();
    try {
      await ensureNamedComposeIntent(ref, name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.composeSaved(name))),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _deploy(
    BuildContext context,
    WidgetRef ref,
    MarketplaceLibrary library,
    ComposeGraph graph,
  ) async {
    try {
      ref.read(composeEditorProvider.notifier).save();
      await ensureNamedComposeIntent(ref, graph.intentName);
      await ref.read(composeDeployProvider.notifier).deploy(
            graph: graph,
            library: library,
          );
      if (!context.mounted) return;
      ref.read(sidebarKeyProvider.notifier).set(IntentsScreen.sidebarKey);
    } catch (_) {
      // Progress already holds the error.
    }
  }
}

class _IntentPicker extends ConsumerWidget {
  const _IntentPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final editor = ref.watch(composeEditorProvider);
    final current = editor.graph.intentName.trim();
    final daemonAsync = ref.watch(intentsStreamProvider);
    final names = composePickerNames(
      saved: ref.read(composeEditorProvider.notifier).savedIntentNames(),
      daemon: [
        for (final intent in daemonAsync.asData?.value ?? const []) intent.name,
      ],
      current: current,
      daemonListReady: daemonAsync.hasValue,
    );
    final selected = names.contains(current) ? current : null;

    return DropdownButtonFormField<String>(
      key: ValueKey('compose-intent-picker-$current'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l10n.composeIntentName,
        hintText: l10n.composeSelectIntent,
        isDense: true,
      ),
      items: [
        for (final name in names)
          DropdownMenuItem(value: name, child: Text(name)),
      ],
      onChanged: (value) {
        if (value == null || value.isEmpty) return;
        ref.read(composeEditorProvider.notifier).openIntent(value);
      },
    );
  }
}

class _ComposePalette extends ConsumerStatefulWidget {
  const _ComposePalette({required this.library});

  final MarketplaceLibrary library;

  @override
  ConsumerState<_ComposePalette> createState() => _ComposePaletteState();
}

class _ComposePaletteState extends ConsumerState<_ComposePalette>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _hasIntent =>
      ref.read(composeEditorProvider).graph.intentName.trim().isNotEmpty;

  void _needIntent(AppLocalizations l10n) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.composeNeedIntent)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ComposeWorkloadTabBar(
          controller: _tabs,
          isScrollable: true,
          servicesLabel: l10n.intentAddTabServices,
          vmsLabel: l10n.intentAddTabVms,
          llmsLabel: l10n.intentAddTabLlms,
        ),
        const SizedBox(height: 8),
        Expanded(child: _tabBody(l10n)),
      ],
    );
  }

  Widget _tabBody(AppLocalizations l10n) {
    switch (_tabs.index) {
      case 1:
        return _vmList(l10n);
      case 2:
        return _llmList(l10n);
      default:
        return _serviceList(l10n);
    }
  }

  Widget _serviceList(AppLocalizations l10n) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListView(
      children: [
        for (final service in widget.library.services)
          _paletteRow(
            key: ValueKey('compose-palette-${service.id}'),
            leading: ServiceIconBadge(
              branding: serviceBranding(service.id, service: service),
              size: 22,
            ),
            title: service.displayName,
            onSurface: onSurface,
            accent: Brand.workloadService,
            onTap: () {
              if (!_ensureIntent(l10n)) return;
              ref.read(composeEditorProvider.notifier).addService(service);
            },
          ),
      ],
    );
  }

  Widget _vmList(AppLocalizations l10n) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ref.watch(imagesProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (images) {
            final ubuntuOnly =
                ref.watch(featureAccessProvider).ubuntuImagesOnly;
            final entries = groupCatalogueEntries(images);
            if (entries.isEmpty) {
              return Center(child: Text(l10n.intentAddVmsEmpty));
            }
            return ListView(
              children: [
                for (final entry in entries)
                  _paletteRow(
                    key: ValueKey(
                      'compose-palette-vm-${_vmId(entry.representative)}',
                    ),
                    leading: DistroLogoBadge(
                      branding: distroBranding(
                        entry.representative.os,
                        isCore: entry.isCore,
                      ),
                      size: 22,
                    ),
                    title: entry.displayTitle(l10n),
                    onSurface: onSurface,
                    accent: Brand.workloadVm,
                    locked: ubuntuOnly &&
                        entry.representative.os.toLowerCase() != 'ubuntu',
                    onTap: () => _addVm(l10n, entry),
                  ),
              ],
            );
          },
        );
  }

  Widget _llmList(AppLocalizations l10n) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ref.watch(loadedModelsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (reply) {
            if (reply.cached.isEmpty) {
              return Center(child: Text(l10n.intentAddLlmsEmpty));
            }
            return ListView(
              children: [
                for (final model in reply.cached)
                  _paletteRow(
                    key: ValueKey('compose-palette-llm-${model.id}'),
                    leading: ModelProviderBadge(
                      branding: brandingForSuggestion(model),
                      size: 22,
                    ),
                    title: model.name.isEmpty ? model.id : model.name,
                    onSurface: onSurface,
                    accent: Brand.workloadAi,
                    onTap: () => _addLlm(l10n, model),
                  ),
              ],
            );
          },
        );
  }

  Widget _paletteRow({
    required Key key,
    required Widget leading,
    required String title,
    required Color onSurface,
    required Color accent,
    required VoidCallback onTap,
    bool locked = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: accent, width: 3),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: Brand.fontFamily),
                    ),
                  ),
                  if (locked)
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: onSurface.withValues(alpha: 0.45),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _ensureIntent(AppLocalizations l10n) {
    if (_hasIntent) return true;
    _needIntent(l10n);
    return false;
  }

  bool _ensureFeature(bool allowed) {
    if (allowed) return true;
    promptFeatureLocked(context, ref);
    return false;
  }

  void _addVm(AppLocalizations l10n, CatalogueEntry entry) {
    if (!_ensureIntent(l10n)) return;
    final ubuntuOnly = ref.read(featureAccessProvider).ubuntuImagesOnly;
    final locked =
        ubuntuOnly && entry.representative.os.toLowerCase() != 'ubuntu';
    if (locked || entry.representative.aliases.isEmpty) {
      if (locked) promptFeatureLocked(context, ref);
      return;
    }
    final image = entry.representative;
    ref.read(composeEditorProvider.notifier).addVm(
          image: image.aliases.first,
          label: entry.displayTitle(l10n),
          diskSpace: '${diskBytesForImage(image)}B',
        );
  }

  void _addLlm(AppLocalizations l10n, ModelSuggestion model) {
    if (!_ensureIntent(l10n)) return;
    if (!_ensureFeature(ref.read(featureAccessProvider).canUseLlms)) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final form = LlmLoadForm.fromJson(readLlmLoadPrefs(prefs, model.id));
    ref.read(composeEditorProvider.notifier).addLlm(
          modelId: model.id,
          label: model.name.isEmpty ? model.id : model.name,
          quant: model.bestQuant,
          runtime: form.runtime,
          ctxSize: suggestedCtxForModel(
                usableContext: model.usableContext.toInt(),
                contextLength: model.contextLength.toInt(),
              ) ??
              defaultLlmCtxSize,
          maxTokens: form.maxTokens,
        );
  }

  static String _vmId(ImageInfo image) =>
      image.aliases.isEmpty ? image.os : image.aliases.first;
}

class _ComposeInspector extends ConsumerStatefulWidget {
  const _ComposeInspector({required this.library});

  final MarketplaceLibrary library;

  @override
  ConsumerState<_ComposeInspector> createState() => _ComposeInspectorState();
}

class _ComposeInspectorState extends ConsumerState<_ComposeInspector> {
  final _role = TextEditingController();
  final _params = <String, TextEditingController>{};
  String? _boundNodeId;

  @override
  void dispose() {
    _role.dispose();
    for (final controller in _params.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncControllers(ComposeNode? node) {
    if (node == null) {
      _boundNodeId = null;
      return;
    }
    if (_boundNodeId != node.id) {
      _boundNodeId = node.id;
      _role.text = node.role;
      for (final controller in _params.values) {
        controller.dispose();
      }
      _params
        ..clear()
        ..addEntries([
          for (final entry in node.manualParams.entries)
            MapEntry(entry.key, TextEditingController(text: entry.value)),
        ]);
    }
  }

  TextEditingController _paramController(String name, String value) {
    return _params.putIfAbsent(name, () => TextEditingController(text: value));
  }

  String _kindLabel(AppLocalizations l10n, ComposeNode node) {
    return switch (node.kind) {
      ComposeNodeKind.vm => l10n.composeKindVm,
      ComposeNodeKind.llm => l10n.composeKindLlm,
      ComposeNodeKind.service => l10n.composeKindService,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final editor = ref.watch(composeEditorProvider);
    final selectedIds = editor.selectedNodeIds;
    final node = selectedIds.length == 1
        ? editor.graph.nodeById(selectedIds.first)
        : null;
    _syncControllers(node);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    if (selectedIds.length > 1) {
      return ListView(
        children: [
          Text(
            l10n.composeInspectorMulti(selectedIds.length),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          LaunchPadButton.destructive(
            onPressed: () =>
                ref.read(composeEditorProvider.notifier).removeSelected(),
            child: Text(l10n.composeDeleteSelected),
          ),
        ],
      );
    }

    if (node == null) {
      return Text(
        l10n.composeInspectorEmpty,
        style: TextStyle(color: onSurface.withValues(alpha: 0.65)),
      );
    }

    final spec = specForNode(node, widget.library);
    final bound = boundInputNames(editor.graph, node.id, widget.library);
    final incoming = [
      for (final edge in editor.graph.edges)
        if (edge.to == node.id) edge,
    ];

    return ListView(
      children: [
        Text(
          l10n.composeInspectorTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          key: ValueKey('compose-role-${node.id}'),
          controller: _role,
          decoration: InputDecoration(
            label: _requiredFieldLabel(context, l10n.composeRoleLabel),
            isDense: true,
          ),
          onChanged: (value) =>
              ref.read(composeEditorProvider.notifier).setRole(node.id, value),
        ),
        const SizedBox(height: 8),
        Text(
          '${_kindLabel(l10n, node)} · ${node.displayLabel}',
          style: TextStyle(
            fontSize: 12,
            color: onSurface.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.composeRequires,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (spec.requires.isEmpty)
          Text(l10n.composeNoPins,
              style: TextStyle(color: onSurface.withValues(alpha: 0.6)))
        else
          for (final contract in composeInputContracts(spec))
            Text.rich(
              TextSpan(
                text: '← ${composePinLabel(contract)}',
                children: [
                  if (composeContractRequired(spec, contract))
                    TextSpan(
                      text: ' $composeRequiredMark',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              style: TextStyle(
                fontSize: 13,
                color: composeContractColor(contract),
                fontWeight: FontWeight.w600,
              ),
            ),
        const SizedBox(height: 12),
        Text(l10n.composeProvides,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (spec.provides.isEmpty)
          Text(l10n.composeNoPins,
              style: TextStyle(color: onSurface.withValues(alpha: 0.6)))
        else
          for (final contract in composeOutputContracts(spec))
            Text(
              '${composePinLabel(contract)}${composeOutputFansOut(contract) ? ' →∗' : ' →'}',
              style: TextStyle(
                fontSize: 13,
                color: composeContractColor(contract),
                fontWeight: FontWeight.w600,
              ),
            ),
        if (composeHttpOutputs(spec).isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.composeHttpOutputs,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final output in composeHttpOutputs(spec))
            Text(
              '→ ${composeHttpOutputLabel(output)}',
              style: TextStyle(
                fontSize: 13,
                color: composeHttpOutputColor,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
        const SizedBox(height: 16),
        for (final input in composeManualInputs(spec))
          if (!bound.contains(input.name))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _paramController(
                  input.name,
                  node.manualParams[input.name] ?? '',
                ),
                decoration: InputDecoration(
                  label: _requiredFieldLabel(
                    context,
                    input.name,
                    required: composeManualInputRequired(
                      spec,
                      input,
                      bound: bound,
                    ),
                  ),
                  helperText: input.description,
                  isDense: true,
                ),
                obscureText: input.secret,
                onChanged: (value) => ref
                    .read(composeEditorProvider.notifier)
                    .setManualParam(node.id, input.name, value),
              ),
            ),
        if (incoming.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final edge in incoming)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(edge.contract, style: const TextStyle(fontSize: 13)),
              trailing: IconButton(
                tooltip: l10n.composeRemoveEdge,
                icon: const Icon(Icons.link_off, size: 18),
                onPressed: () =>
                    ref.read(composeEditorProvider.notifier).removeEdge(edge),
              ),
            ),
        ],
        const SizedBox(height: 12),
        LaunchPadButton.destructive(
          onPressed: () =>
              ref.read(composeEditorProvider.notifier).removeNode(node.id),
          child: Text(l10n.composeDeleteNode),
        ),
      ],
    );
  }
}

Widget _requiredFieldLabel(
  BuildContext context,
  String label, {
  bool required = true,
}) {
  if (!required) return Text(label);
  final error = Theme.of(context).colorScheme.error;
  return Tooltip(
    message: AppLocalizations.of(context)!.composeRequiredTooltip,
    child: Text.rich(
      TextSpan(
        text: label,
        children: [
          TextSpan(
            text: ' $composeRequiredMark',
            style: TextStyle(color: error, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

/// Opens the compose canvas on [intentName], creating a blank graph if needed.
void openIntentInCompose(WidgetRef ref, String intentName) {
  ref.read(composeEditorProvider.notifier).openIntent(intentName);
  ref.read(sidebarKeyProvider.notifier).set(ComposeScreen.sidebarKey);
}

/// Names a new intent, creates it on the daemon when available, and opens it.
Future<String?> showNewComposeIntentDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  String? error;
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        shape: const Border(),
        title: Text(l10n.composeNewIntent),
        content: SizedBox(
          width: CompactLayout.dialogWidth(dialogContext, 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('compose-new-intent-name'),
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.composeIntentName,
                  hintText: l10n.composeIntentNameHint,
                ),
                onSubmitted: (value) {
                  final trimmed = value.trim();
                  if (trimmed.isEmpty) {
                    setDialogState(
                      () => error = l10n.composeNeedIntent,
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, trimmed);
                },
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonCancel),
          ),
          LaunchPadButton.primary(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) {
                setDialogState(() => error = l10n.composeNeedIntent);
                return;
              }
              Navigator.pop(dialogContext, trimmed);
            },
            child: Text(l10n.composeCreateIntent),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty) return null;
  ref.read(composeEditorProvider.notifier).openIntent(name);
  ref.read(composeEditorProvider.notifier).save();
  try {
    await ensureNamedComposeIntent(ref, name);
  } catch (_) {
    // Graph is still saved locally; deploy/save can retry the daemon.
  }
  return name;
}
