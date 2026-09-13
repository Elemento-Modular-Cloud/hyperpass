import 'dart:math';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/feature_access.dart';
import '../auth/feature_lock.dart';
import '../brand.dart';
import '../catalogue/catalogue.dart';
import '../catalogue/catalogue_entry.dart';
import '../catalogue/launch_form.dart';
import '../distro_branding.dart';
import '../l10n/app_localizations.dart';
import '../layout/compact_layout.dart';
import '../llm/catalogue/model_branding.dart';
import '../llm/llm_features.dart';
import '../llm/llm_load.dart';
import '../llm/llm_load_form.dart';
import '../llm/llm_load_prefs.dart';
import '../llm/providers.dart';
import '../notifications.dart';
import '../providers.dart';
import '../services/compose/compose_graph.dart';
import '../services/service_branding.dart';
import '../services/service_intent_member.dart';
import '../services/service_library.dart';
import '../widgets/launchpad_button.dart';
import '../widgets/rounded_search_field.dart';

const _inferenceBackendIds = {
  'llamacpp',
  if (enableMlxBackend) 'mlx',
};

/// Opens a picker of marketplace services, VM images, and downloaded LLMs
/// to launch as members of [intentName].
Future<void> showAddMemberDialog(
  BuildContext context,
  WidgetRef ref,
  String intentName, {
  Iterable<String> existingRoles = const [],
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AddIntentMemberDialog(
      intentName: intentName,
      existingRoles: {...existingRoles},
    ),
  );
}

class _AddIntentMemberDialog extends ConsumerStatefulWidget {
  const _AddIntentMemberDialog({
    required this.intentName,
    required this.existingRoles,
  });

  final String intentName;
  final Set<String> existingRoles;

  @override
  ConsumerState<_AddIntentMemberDialog> createState() =>
      _AddIntentMemberDialogState();
}

class _AddIntentMemberDialogState extends ConsumerState<_AddIntentMemberDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final Set<String> _taken;
  final _search = TextEditingController();
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _taken = {...widget.existingRoles};
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = _search.text.trim().toLowerCase();

    return AlertDialog(
      shape: const Border(),
      title: Text(l10n.intentAddServiceTitle(widget.intentName)),
      content: SizedBox(
        width: CompactLayout.dialogWidth(context, 480),
        height: min(520, MediaQuery.sizeOf(context).height * 0.65),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.intentAddServiceSubtitle,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: l10n.intentAddTabServices),
                Tab(text: l10n.intentAddTabVms),
                Tab(text: l10n.intentAddTabLlms),
              ],
            ),
            const SizedBox(height: 12),
            RoundedSearchField(
              width: null,
              controller: _search,
              hint: l10n.intentAddServiceSearch,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(child: _tabBody(l10n, query)),
          ],
        ),
      ),
      actions: [
        LaunchPadButton.primary(
          onPressed: _busyId == null ? () => Navigator.pop(context) : null,
          child: Text(l10n.intentAddServiceDone),
        ),
      ],
    );
  }

  Widget _tabBody(AppLocalizations l10n, String query) {
    switch (_tabs.index) {
      case 1:
        return _vmList(l10n, query);
      case 2:
        return _llmList(l10n, query);
      default:
        return _serviceList(l10n, query);
    }
  }

  Widget _serviceList(AppLocalizations l10n, String query) {
    return ref.watch(marketplaceLibraryProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (library) {
            final services = [
              for (final service in library.services)
                if (_matches(
                  query,
                  [service.displayName, service.id, service.description],
                ))
                  service,
            ];
            if (services.isEmpty) {
              return Center(child: Text(l10n.intentAddServiceEmpty));
            }
            return ListView(
              children: [
                for (final service in services)
                  _row(
                    key: ValueKey('intent-add-service-${service.id}'),
                    leading: ServiceIconBadge(
                      branding: serviceBranding(service.id, service: service),
                      size: 28,
                    ),
                    title: service.displayName,
                    subtitle: service.id,
                    busy: _busyId == service.id,
                    onTap: () => _addService(service),
                  ),
              ],
            );
          },
        );
  }

  Widget _vmList(AppLocalizations l10n, String query) {
    return ref.watch(imagesProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (images) {
            final ubuntuOnly =
                ref.watch(featureAccessProvider).ubuntuImagesOnly;
            final entries = groupCatalogueEntries(images)
                .where((entry) => entry.matchesQuery(query))
                .toList();
            if (entries.isEmpty) {
              return Center(child: Text(l10n.intentAddVmsEmpty));
            }
            return ListView(
              children: [
                for (final entry in entries)
                  _row(
                    key: ValueKey(
                      'intent-add-vm-${entry.representative.aliases.isEmpty ? entry.representative.os : entry.representative.aliases.first}',
                    ),
                    leading: DistroLogoBadge(
                      branding: distroBranding(
                        entry.representative.os,
                        isCore: entry.isCore,
                      ),
                      size: 28,
                    ),
                    title: entry.displayTitle(l10n),
                    subtitle: imageName(entry.representative),
                    busy: _busyId == _vmBusyId(entry.representative),
                    locked: ubuntuOnly &&
                        entry.representative.os.toLowerCase() != 'ubuntu',
                    onTap: () => _addVm(
                      entry.representative,
                      locked: ubuntuOnly &&
                          entry.representative.os.toLowerCase() != 'ubuntu',
                    ),
                  ),
              ],
            );
          },
        );
  }

  Widget _llmList(AppLocalizations l10n, String query) {
    return ref.watch(loadedModelsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (reply) {
            final models = [
              for (final model in reply.cached)
                if (_matches(query, [
                  model.name,
                  model.id,
                  model.provider,
                  model.bestQuant,
                ]))
                  model,
            ];
            if (models.isEmpty) {
              return Center(child: Text(l10n.intentAddLlmsEmpty));
            }
            return ListView(
              children: [
                for (final model in models)
                  _row(
                    key: ValueKey('intent-add-llm-${model.id}'),
                    leading: ModelProviderBadge(
                      branding: brandingForSuggestion(model),
                      size: 28,
                    ),
                    title: model.name.isEmpty ? model.id : model.name,
                    subtitle: [
                      model.id,
                      if (model.bestQuant.isNotEmpty) model.bestQuant,
                    ].join(' · '),
                    busy: _busyId == model.id,
                    onTap: () => _addLlm(model),
                  ),
              ],
            );
          },
        );
  }

  Widget _row({
    required Key key,
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool busy = false,
    bool locked = false,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListTile(
      key: key,
      leading: leading,
      title: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: Brand.fontFamily),
      ),
      subtitle: Text(
        subtitle,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          color: onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : locked
              ? Icon(Icons.lock_outline,
                  size: 18, color: onSurface.withValues(alpha: 0.45))
              : null,
      enabled: _busyId == null,
      onTap: onTap,
    );
  }

  Future<void> _addService(MarketplaceService service) async {
    if (!_ensureFeature(ref.read(featureAccessProvider).canUseServices)) {
      return;
    }
    final role = suggestComposeRole(service.id, _taken);
    setState(() {
      _busyId = service.id;
      _error = null;
    });
    try {
      final member = await buildServiceIntentMemberWithGatewayCa(
        service: service,
        role: role,
      );
      await _submit(
        member,
        label: service.displayName,
      );
      ref.read(serviceInstanceBindingsProvider.notifier).bind(
            intentMemberInstanceName(widget.intentName, role),
            service.id,
          );
      _taken.add(role);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _addVm(ImageInfo image, {required bool locked}) async {
    if (locked || image.aliases.isEmpty) {
      if (locked) promptFeatureLocked(context, ref);
      return;
    }
    final alias = image.aliases.first;
    final role = suggestComposeRole(alias, _taken);
    setState(() {
      _busyId = _vmBusyId(image);
      _error = null;
    });
    try {
      await _submit(
        IntentMemberRequest(
          role: role,
          image: alias,
          numCores: defaultCpus,
          memSize: '${defaultRam}B',
          diskSpace: '${diskBytesForImage(image)}B',
        ),
        label: imageName(image),
      );
      _taken.add(role);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _addLlm(ModelSuggestion model) async {
    if (!_ensureFeature(ref.read(featureAccessProvider).canUseLlms)) return;
    final backends = await ref.read(llmBackendsProvider.future);
    if (!mounted) return;
    final form = LlmLoadForm.fromJson(
      readLlmLoadPrefs(ref.read(sharedPreferencesProvider), model.id),
      suggestedCtx: suggestedCtxForModel(
        usableContext: model.usableContext.toInt(),
        contextLength: model.contextLength.toInt(),
      ),
    );
    final runtime = _pickRuntime(backends, form.runtime);
    if (runtime == null) {
      setState(() =>
          _error = AppLocalizations.of(context)!.modelsNoRuntimeAvailable);
      return;
    }
    form.runtime = runtime;
    final role = suggestComposeRole(model.id, _taken);
    setState(() {
      _busyId = model.id;
      _error = null;
    });
    try {
      await _submit(
        IntentMemberRequest(
          role: role,
          modelId: model.id,
          quant: model.bestQuant,
          runtime: form.runtime,
          ctxSize: form.ctxSize,
          maxTokens: form.maxTokens,
        ),
        label: model.name.isEmpty ? model.id : model.name,
      );
      _taken.add(role);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _submit(IntentMemberRequest member, {required String label}) {
    final grpc = ref.read(grpcClientProvider);
    final op = grpc.intentAddMember(
      IntentAddMemberRequest(name: widget.intentName, members: [member]),
    );
    ref.read(notificationsProvider.notifier).addOperation(
          op,
          loading: 'Adding $label to intent ${widget.intentName}…',
          onSuccess: (reply) {
            final message = reply?.replyMessage;
            return message != null && message.isNotEmpty
                ? message
                : 'Added $label to intent ${widget.intentName}';
          },
          onError: (error) => '$error',
        );
    return op.then((_) => ref.invalidate(intentsStreamProvider));
  }

  bool _ensureFeature(bool allowed) {
    if (allowed) return true;
    promptFeatureLocked(context, ref);
    return false;
  }

  static String _vmBusyId(ImageInfo image) =>
      image.aliases.isEmpty ? image.os : image.aliases.first;

  static String? _pickRuntime(ListLlmBackendsReply backends, String preferred) {
    final ready = [
      for (final backend in backends.backends)
        if (backend.status == 'ready' &&
            _inferenceBackendIds.contains(backend.id))
          backend.id,
    ];
    if (ready.contains(preferred)) return preferred;
    return ready.isEmpty ? null : ready.first;
  }

  static bool _matches(String query, List<String> fields) {
    if (query.isEmpty) return true;
    return fields.any((field) => field.toLowerCase().contains(query));
  }
}
