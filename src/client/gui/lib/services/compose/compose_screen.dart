import 'dart:async';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/feature_access.dart';
import '../../auth/feature_lock.dart';
import '../../brand.dart';
import '../../catalogue/catalogue.dart';
import '../../catalogue/catalogue_entry.dart';
import '../../catalogue/launch_form.dart';
import '../../distro_branding.dart';
import '../../intents/composition_load.dart';
import '../../intents/intents_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../layout/compact_layout.dart';
import '../../llm/catalogue/model_branding.dart';
import '../../cloud_init/cloud_init_store.dart';
import '../../llm/llm_features.dart';
import '../../llm/llm_load.dart';
import '../../llm/llm_load_form.dart';
import '../../llm/llm_load_prefs.dart';
import '../../llm/providers.dart';
import '../../notifications.dart';
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
                          onPressed: () =>
                              showNewComposeIntentDialog(context, ref),
                          child: Text(l10n.composeNewIntent),
                        ),
                        LaunchPadButton.secondary(
                          onPressed: !hasIntent
                              ? null
                              : () => _save(context, ref),
                          child: Text(l10n.composeSave),
                        ),
                        LaunchPadButton.primary(
                          onPressed: issues.isNotEmpty
                              ? null
                              : () =>
                                  _deploy(context, ref, library, editor.graph),
                          child: Text(l10n.composeDeployAction),
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
            if (progress?.running == true && progress?.message != null) ...[
              const SizedBox(height: 8),
              Text(
                progress!.message!,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
            if (issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                issues.first.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (hasIntent) ...[
              const SizedBox(height: 10),
              _ComposeLoadBar(library: library, graph: editor.graph),
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
    final l10n = AppLocalizations.of(context)!;
    ref.read(composeEditorProvider.notifier).save();
    await ensureNamedComposeIntent(ref, graph.intentName);
    if (!context.mounted) return;

    final op = ref.read(composeDeployProvider.notifier).deploy(
          graph: graph,
          library: library,
        );
    ref.read(notificationsProvider.notifier).addOperation(
          op,
          loading: l10n.composeDeploying,
          onSuccess: (runName) => l10n.composeDeployStarted(runName),
          onError: (error) => '$error',
        );
    ref.read(sidebarKeyProvider.notifier).set(IntentsScreen.sidebarKey);
  }
}

class _ComposeLoadBar extends ConsumerWidget {
  const _ComposeLoadBar({required this.library, required this.graph});

  final MarketplaceLibrary library;
  final ComposeGraph graph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daemon = ref.watch(daemonInfoProvider).asData?.value;
    if (daemon == null) return const SizedBox.shrink();
    return CompositionLoadMeters(
      key: const ValueKey('compose-load-meters'),
      load: compositionLoadFromGraph(
        graph: graph,
        library: library,
        cpuHost: daemon.cpus,
        memHost: daemon.memory.toInt(),
      ),
    );
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
    // SharedPreferences graphs outlive daemon deletes (e.g. CLI purge). Drop
    // orphans so recreating a name cannot resurrect an old topology.
    ref.listen(intentsStreamProvider, (previous, next) {
      final intents = next.asData?.value;
      if (intents == null) return;
      ref.read(composeEditorProvider.notifier).pruneOrphanedGraphs([
        for (final intent in intents) intent.name,
      ]);
    });
    final List<String> daemonNames = [
      for (final intent in daemonAsync.asData?.value ?? const <IntentInfo>[])
        intent.name,
    ];
    if (daemonAsync.hasValue) {
      final live = daemonNames.toSet();
      final saved = ref.read(composeEditorProvider.notifier).savedIntentNames();
      if (saved.any((name) => !live.contains(name))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(composeEditorProvider.notifier)
              .pruneOrphanedGraphs(daemonNames);
        });
      }
    }
    final names = composePickerNames(
      saved: ref.read(composeEditorProvider.notifier).savedIntentNames(),
      daemon: daemonNames,
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
    return ListView(
      children: [
        _paletteRow(
          key: const ValueKey('compose-palette-llm-standard'),
          leading: Icon(
            Icons.memory_outlined,
            size: 22,
            color: Brand.workloadAi,
          ),
          title: l10n.composeLlmStandardBlock,
          onSurface: onSurface,
          accent: Brand.workloadAi,
          onTap: () => _addStandardLlm(l10n),
        ),
        _paletteRow(
          key: const ValueKey('compose-palette-llm-cloud'),
          leading: Icon(
            Icons.cloud_outlined,
            size: 22,
            color: Brand.info,
          ),
          title: l10n.composeLlmCloudBlock,
          onSurface: onSurface,
          accent: Brand.info,
          onTap: () => _addCloudLlm(l10n),
        ),
      ],
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

  Future<void> _addStandardLlm(AppLocalizations l10n) async {
    if (!_ensureIntent(l10n)) return;
    if (!_ensureFeature(ref.read(featureAccessProvider).canUseLlms)) return;
    final model = await _pickCatalogModel(l10n);
    if (!mounted || model == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final form = LlmLoadForm.fromJson(readLlmLoadPrefs(prefs, model.id));
    final backends = ref.read(llmBackendsProvider).asData?.value;
    final readyIds = {
      for (final backend in backends?.backends ?? const [])
        if (backend.status == 'ready' && inferenceBackendIds.contains(backend.id))
          backend.id,
    };
    var runtime = form.runtime;
    if (model.runtime.isNotEmpty && readyIds.contains(model.runtime)) {
      runtime = model.runtime;
    } else if (!readyIds.contains(runtime) && readyIds.isNotEmpty) {
      runtime = readyIds.first;
    }
    ref.read(composeEditorProvider.notifier).addLlm(
          modelId: model.id,
          llmMode: ComposeLlmMode.standard,
          label: model.name.isEmpty ? model.id : model.name,
          quant: model.bestQuant,
          runtime: runtime,
          ctxSize: suggestedCtxForModel(
                usableContext: model.usableContext.toInt(),
                contextLength: model.contextLength.toInt(),
              ) ??
              defaultLlmCtxSize,
          maxTokens: form.maxTokens,
        );
  }

  Future<void> _addCloudLlm(AppLocalizations l10n) async {
    if (!_ensureIntent(l10n)) return;
    if (!_ensureFeature(ref.read(featureAccessProvider).canUseLlms)) return;
    final model = await _pickCloudModel(l10n);
    if (!mounted || model == null) return;
    final label = model.openaiId.isNotEmpty
        ? model.openaiId
        : (model.modelId.isNotEmpty ? model.modelId : 'cloud');
    ref.read(composeEditorProvider.notifier).addLlm(
          modelId: model.openaiId.isNotEmpty ? model.openaiId : model.modelId,
          llmMode: ComposeLlmMode.cloud,
          label: label,
        );
  }

  Future<ModelSuggestion?> _pickCatalogModel(AppLocalizations l10n) {
    return showDialog<ModelSuggestion>(
      context: context,
      builder: (context) => const _ComposeCatalogPickerDialog(),
    );
  }

  Future<LoadedModelInfo?> _pickCloudModel(AppLocalizations l10n) {
    return showDialog<LoadedModelInfo>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final async = ref.watch(loadedModelsProvider);
          return _ComposeModelPickerDialog<LoadedModelInfo>(
            title: l10n.composeLlmPickCloud,
            emptyLabel: l10n.composeLlmCloudEmpty,
            models: async.whenData(
              (reply) => [
                for (final m in reply.models)
                  if (isRemoteLlmModel(m)) m,
              ],
            ),
            itemKey: (m) => 'compose-pick-cloud-${m.instanceId}',
            titleOf: (m) =>
                m.openaiId.isNotEmpty ? m.openaiId : m.modelId,
            subtitleOf: (m) => [
              if (m.ownedBy.isNotEmpty) m.ownedBy,
              if (m.providerId.isNotEmpty) m.providerId,
            ].where((s) => s.isNotEmpty).join(' · '),
            leadingOf: (m) => ModelProviderBadge(
              branding: brandingForLoaded(m),
              size: 28,
            ),
          );
        },
      ),
    );
  }

  static String _vmId(ImageInfo image) =>
      image.aliases.isEmpty ? image.os : image.aliases.first;
}

class _ComposeCatalogPickerDialog extends ConsumerStatefulWidget {
  const _ComposeCatalogPickerDialog();

  @override
  ConsumerState<_ComposeCatalogPickerDialog> createState() =>
      _ComposeCatalogPickerDialogState();
}

class _ComposeCatalogPickerDialogState
    extends ConsumerState<_ComposeCatalogPickerDialog> {
  final _query = TextEditingController();
  var _debounced = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _debounced = value.trim());
    });
  }

  void _useTypedId() {
    final id = _query.text.trim();
    if (id.isEmpty) return;
    Navigator.pop(
      context,
      ModelSuggestion(id: id, name: id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(composeCatalogModelsProvider(_debounced));
    final typed = _query.text.trim();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AlertDialog(
      title: Text(l10n.composeLlmPickCatalog),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: l10n.composeLlmModelIdHint,
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {});
                _onQueryChanged(value);
              },
              onSubmitted: (_) => _useTypedId(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('compose-catalog-use-id'),
                onPressed: typed.isEmpty ? null : _useTypedId,
                icon: const Icon(Icons.check, size: 18),
                label: Text(
                  typed.isEmpty
                      ? l10n.composeLlmUseModelId
                      : '${l10n.composeLlmUseModelId}: $typed',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('$error')),
                data: (result) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (result.hint.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            result.hint,
                            style: TextStyle(
                              fontFamily: Brand.fontFamily,
                              fontSize: 12,
                              color: onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      if (!result.catalogAvailable && result.models.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Suggestions',
                            style: TextStyle(
                              fontFamily: Brand.fontFamily,
                              fontWeight: FontWeight.w600,
                              color: onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      Expanded(
                        child: result.models.isEmpty
                            ? Center(child: Text(l10n.composeLlmCatalogEmpty))
                            : ListView.builder(
                                itemCount: result.models.length,
                                itemBuilder: (context, index) {
                                  final model = result.models[index];
                                  final title = model.name.isEmpty
                                      ? model.id
                                      : model.name;
                                  final subtitle = [
                                    model.id,
                                    if (model.bestQuant.isNotEmpty)
                                      model.bestQuant,
                                    if (model.provider.isNotEmpty)
                                      model.provider,
                                  ].join(' · ');
                                  return ListTile(
                                    key: ValueKey(
                                      'compose-pick-catalog-${model.id}',
                                    ),
                                    leading: ModelProviderBadge(
                                      branding: brandingForSuggestion(model),
                                      size: 28,
                                    ),
                                    title: Text(
                                      title,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: Brand.fontFamily,
                                      ),
                                    ),
                                    subtitle: Text(
                                      subtitle,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: Brand.fontFamily,
                                        color: onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    onTap: () =>
                                        Navigator.pop(context, model),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}

class _ComposeModelPickerDialog<T> extends StatelessWidget {
  const _ComposeModelPickerDialog({
    required this.title,
    required this.emptyLabel,
    required this.models,
    required this.itemKey,
    required this.titleOf,
    required this.subtitleOf,
    required this.leadingOf,
  });

  final String title;
  final String emptyLabel;
  final AsyncValue<List<T>> models;
  final String Function(T) itemKey;
  final String Function(T) titleOf;
  final String Function(T) subtitleOf;
  final Widget Function(T) leadingOf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        height: 420,
        child: models.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (items) {
            if (items.isEmpty) {
              return Center(child: Text(emptyLabel));
            }
            return _ComposeModelPickerList<T>(
              items: items,
              itemKey: itemKey,
              titleOf: titleOf,
              subtitleOf: subtitleOf,
              leadingOf: leadingOf,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}

class _ComposeModelPickerList<T> extends StatefulWidget {
  const _ComposeModelPickerList({
    required this.items,
    required this.itemKey,
    required this.titleOf,
    required this.subtitleOf,
    required this.leadingOf,
  });

  final List<T> items;
  final String Function(T) itemKey;
  final String Function(T) titleOf;
  final String Function(T) subtitleOf;
  final Widget Function(T) leadingOf;

  @override
  State<_ComposeModelPickerList<T>> createState() =>
      _ComposeModelPickerListState<T>();
}

class _ComposeModelPickerListState<T> extends State<_ComposeModelPickerList<T>> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final filtered = [
      for (final item in widget.items)
        if (q.isEmpty ||
            widget.titleOf(item).toLowerCase().contains(q) ||
            widget.subtitleOf(item).toLowerCase().contains(q))
          item,
    ];
    return Column(
      children: [
        TextField(
          controller: _query,
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 20),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matches'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return ListTile(
                      key: ValueKey(widget.itemKey(item)),
                      leading: widget.leadingOf(item),
                      title: Text(
                        widget.titleOf(item),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: Brand.fontFamily),
                      ),
                      subtitle: Text(
                        widget.subtitleOf(item),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ComposeInspector extends ConsumerStatefulWidget {
  const _ComposeInspector({required this.library});

  final MarketplaceLibrary library;

  @override
  ConsumerState<_ComposeInspector> createState() => _ComposeInspectorState();
}

class _ComposeInspectorState extends ConsumerState<_ComposeInspector> {
  final _role = TextEditingController();
  final _cpu = TextEditingController();
  final _ram = TextEditingController();
  final _disk = TextEditingController();
  final _ctx = TextEditingController();
  final _maxTokens = TextEditingController();
  final _quant = TextEditingController();
  final _runtime = TextEditingController();
  final _params = <String, TextEditingController>{};
  String? _boundNodeId;

  @override
  void dispose() {
    _role.dispose();
    _cpu.dispose();
    _ram.dispose();
    _disk.dispose();
    _ctx.dispose();
    _maxTokens.dispose();
    _quant.dispose();
    _runtime.dispose();
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
      final service =
          node.isService ? widget.library.lookup(node.serviceId) : null;
      _cpu.text = '${composeResolvedCpus(node, service)}';
      _ram.text = _gibField(composeResolvedMemBytes(node, service));
      _disk.text = _gibField(composeResolvedDiskBytes(node, service));
      _ctx.text = '${composeResolvedCtxSize(node)}';
      _maxTokens.text = '${node.maxTokens}';
      _quant.text = node.quant;
      _runtime.text = composeResolvedRuntime(node);
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

  static String _gibField(int bytes) {
    final gibi = bytes / composeGibibyte;
    if ((gibi - gibi.round()).abs() < 0.05) return '${gibi.round()}';
    return gibi.toStringAsFixed(1);
  }

  static int? _gibToBytes(String raw) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) return null;
    return (parsed * composeGibibyte).round();
  }

  TextEditingController _paramController(String name, String value) {
    return _params.putIfAbsent(name, () => TextEditingController(text: value));
  }

  String _kindLabel(AppLocalizations l10n, ComposeNode node) {
    return switch (node.kind) {
      ComposeNodeKind.vm => l10n.composeKindVm,
      ComposeNodeKind.llm => node.isCloudLlm
          ? l10n.composeLlmCloudBlock
          : l10n.composeLlmStandardBlock,
      ComposeNodeKind.service => l10n.composeKindService,
    };
  }

  String _runtimeLabel(AppLocalizations l10n, String id) {
    return switch (id) {
      'llamacpp' => l10n.modelsRuntimeLlama,
      'mlx' => l10n.modelsRuntimeMlx,
      'vllm' => l10n.modelsRuntimeVllm,
      _ => id,
    };
  }

  List<Widget> _llmFields(AppLocalizations l10n, ComposeNode node) {
    if (node.isCloudLlm) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            key: ValueKey('compose-llm-model-${node.id}'),
            onPressed: () async {
              final model = await showDialog<LoadedModelInfo>(
                context: context,
                builder: (context) => Consumer(
                  builder: (context, ref, _) {
                    final async = ref.watch(loadedModelsProvider);
                    return _ComposeModelPickerDialog<LoadedModelInfo>(
                      title: l10n.composeLlmPickCloud,
                      emptyLabel: l10n.composeLlmCloudEmpty,
                      models: async.whenData(
                        (reply) => [
                          for (final m in reply.models)
                            if (isRemoteLlmModel(m)) m,
                        ],
                      ),
                      itemKey: (m) => 'compose-pick-cloud-${m.instanceId}',
                      titleOf: (m) =>
                          m.openaiId.isNotEmpty ? m.openaiId : m.modelId,
                      subtitleOf: (m) => [
                        if (m.ownedBy.isNotEmpty) m.ownedBy,
                        if (m.providerId.isNotEmpty) m.providerId,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      leadingOf: (m) => ModelProviderBadge(
                        branding: brandingForLoaded(m),
                        size: 28,
                      ),
                    );
                  },
                ),
              );
              if (model == null) return;
              final id =
                  model.openaiId.isNotEmpty ? model.openaiId : model.modelId;
              ref.read(composeEditorProvider.notifier).setLlmModel(
                    node.id,
                    modelId: id,
                    label: id,
                    runtime: 'openai-compat',
                    quant: '',
                    ctxSize: 0,
                    maxTokens: 0,
                  );
            },
            icon: const Icon(Icons.cloud_outlined, size: 18),
            label: Text(
              node.modelId.isEmpty
                  ? l10n.composeLlmPickCloud
                  : node.modelId,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ];
    }

    final backends = ref.watch(llmBackendsProvider).asData?.value;
    final ready = {
      for (final backend in backends?.backends ?? const [])
        if (backend.status == 'ready' && inferenceBackendIds.contains(backend.id))
          backend.id,
    };
    final runtime = composeResolvedRuntime(node);
    ready.add(runtime);

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton.icon(
          key: ValueKey('compose-llm-model-${node.id}'),
          onPressed: () async {
            final model = await showDialog<ModelSuggestion>(
              context: context,
              builder: (context) => const _ComposeCatalogPickerDialog(),
            );
            if (model == null) return;
            final prefs = ref.read(sharedPreferencesProvider);
            final form =
                LlmLoadForm.fromJson(readLlmLoadPrefs(prefs, model.id));
            var chosenRuntime = form.runtime.isEmpty
                ? composeResolvedRuntime(node)
                : form.runtime;
            if (model.runtime.isNotEmpty && ready.contains(model.runtime)) {
              chosenRuntime = model.runtime;
            }
            ref.read(composeEditorProvider.notifier).setLlmModel(
                  node.id,
                  modelId: model.id,
                  label: model.name.isEmpty ? model.id : model.name,
                  quant: model.bestQuant,
                  runtime: chosenRuntime,
                  ctxSize: suggestedCtxForModel(
                        usableContext: model.usableContext.toInt(),
                        contextLength: model.contextLength.toInt(),
                      ) ??
                      composeResolvedCtxSize(node),
                  maxTokens: form.maxTokens,
                );
          },
          icon: const Icon(Icons.memory_outlined, size: 18),
          label: Text(
            node.modelId.isEmpty
                ? l10n.composeLlmPickCatalog
                : node.modelId,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      if (ready.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DropdownButtonFormField<String>(
            key: ValueKey('compose-runtime-${node.id}'),
            initialValue: runtime,
            isDense: true,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.modelsRuntimeLabel,
              isDense: true,
            ),
            items: [
              for (final id in ready)
                DropdownMenuItem(value: id, child: Text(_runtimeLabel(l10n, id))),
            ],
            onChanged: (value) {
              if (value == null) return;
              ref
                  .read(composeEditorProvider.notifier)
                  .setResources(node.id, runtime: value);
            },
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            key: ValueKey('compose-runtime-${node.id}'),
            controller: _runtime,
            decoration: InputDecoration(
              labelText: l10n.modelsRuntimeLabel,
              isDense: true,
            ),
            onChanged: (value) {
              final trimmed = value.trim();
              if (trimmed.isEmpty) return;
              ref
                  .read(composeEditorProvider.notifier)
                  .setResources(node.id, runtime: trimmed);
            },
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: ValueKey('compose-quant-${node.id}'),
          controller: _quant,
          decoration: InputDecoration(
            labelText: l10n.modelsDetailQuant,
            isDense: true,
          ),
          onChanged: (value) => ref
              .read(composeEditorProvider.notifier)
              .setResources(node.id, quant: value.trim()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: ValueKey('compose-ctx-${node.id}'),
          controller: _ctx,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.composeResourceContext,
            isDense: true,
          ),
          onChanged: (value) {
            final parsed = int.tryParse(value.trim());
            if (parsed == null || parsed <= 0) return;
            ref
                .read(composeEditorProvider.notifier)
                .setResources(node.id, ctxSize: parsed);
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: ValueKey('compose-max-tokens-${node.id}'),
          controller: _maxTokens,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.modelsMaxTokensLabel,
            helperText: l10n.modelsMaxTokensHelper,
            isDense: true,
          ),
          onChanged: (value) {
            final parsed = int.tryParse(value.trim());
            if (parsed == null || parsed < 0) return;
            ref
                .read(composeEditorProvider.notifier)
                .setResources(node.id, maxTokens: parsed);
          },
        ),
      ),
    ];
  }

  List<Widget> _vmResourceFields(AppLocalizations l10n, ComposeNode node) {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: ValueKey('compose-cpu-${node.id}'),
          controller: _cpu,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.composeResourceCpu,
            isDense: true,
          ),
          onChanged: (value) {
            final parsed = int.tryParse(value.trim());
            if (parsed == null || parsed <= 0) return;
            ref
                .read(composeEditorProvider.notifier)
                .setResources(node.id, numCores: parsed);
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: ValueKey('compose-ram-${node.id}'),
          controller: _ram,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.composeResourceRam,
            isDense: true,
          ),
          onChanged: (value) {
            final bytes = _gibToBytes(value);
            if (bytes == null) return;
            ref
                .read(composeEditorProvider.notifier)
                .setResources(node.id, memBytes: bytes);
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: ValueKey('compose-disk-${node.id}'),
          controller: _disk,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.composeResourceStorage,
            isDense: true,
          ),
          onChanged: (value) {
            final bytes = _gibToBytes(value);
            if (bytes == null) return;
            ref
                .read(composeEditorProvider.notifier)
                .setResources(node.id, diskBytes: bytes);
          },
        ),
      ),
    ];
  }

  Widget _cloudInitField(AppLocalizations l10n, ComposeNode node) {
    final configs =
        ref.watch(cloudInitConfigsProvider).asData?.value ?? const [];
    final names = {
      '',
      for (final config in configs) config.name,
      if (node.cloudInitName.isNotEmpty) node.cloudInitName,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        key: ValueKey('compose-cloud-init-${node.id}'),
        initialValue: node.cloudInitName,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.cloudInitLabel,
          isDense: true,
        ),
        items: [
          for (final name in names)
            DropdownMenuItem(
              value: name,
              child: Text(name.isEmpty ? l10n.cloudInitLaunchNone : name),
            ),
        ],
        onChanged: (value) => ref
            .read(composeEditorProvider.notifier)
            .setResources(node.id, cloudInitName: value ?? ''),
      ),
    );
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
        Text(l10n.composeResources,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (node.kind == ComposeNodeKind.llm)
          ..._llmFields(l10n, node)
        else ...[
          ..._vmResourceFields(l10n, node),
          if (node.kind == ComposeNodeKind.vm) _cloudInitField(l10n, node),
        ],
        const SizedBox(height: 8),
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
  ref.read(composeEditorProvider.notifier).startFreshIntent(name);
  try {
    await ensureNamedComposeIntent(ref, name);
  } catch (_) {
    // Graph is still saved locally; deploy/save can retry the daemon.
  }
  return name;
}
