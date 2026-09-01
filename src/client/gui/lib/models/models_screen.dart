import 'dart:async';

import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';

import '../brand.dart';
import '../copyable_text.dart';
import '../l10n/app_localizations.dart';
import '../page_surface.dart';
import '../providers.dart';
import '../tooltip.dart';
import '../vm_table/table.dart' as vmtable;
import '../vm_details/memory_usage.dart';

final loadedModelsProvider = FutureProvider((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return ListModelsReply();
  }
  return ref.watch(grpcClientProvider).listModels();
});

final llmBackendsProvider = FutureProvider((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return ListLlmBackendsReply();
  }
  return ref.watch(grpcClientProvider).listLlmBackends();
});

class CatalogFilters {
  final String search;
  final String minFit;
  final String runtime;

  const CatalogFilters({
    this.search = '',
    this.minFit = '',
    this.runtime = '',
  });

  CatalogFilters copyWith({
    String? search,
    String? minFit,
    String? runtime,
  }) {
    return CatalogFilters(
      search: search ?? this.search,
      minFit: minFit ?? this.minFit,
      runtime: runtime ?? this.runtime,
    );
  }
}

class CatalogFiltersNotifier extends Notifier<CatalogFilters> {
  @override
  CatalogFilters build() => const CatalogFilters();

  void setSearch(String value) => state = state.copyWith(search: value);
  void setMinFit(String value) => state = state.copyWith(minFit: value);
  void setRuntime(String value) => state = state.copyWith(runtime: value);
}

final catalogFiltersProvider =
    NotifierProvider<CatalogFiltersNotifier, CatalogFilters>(
  CatalogFiltersNotifier.new,
);

class DebouncedCatalogQuery extends Notifier<String> {
  Timer? _timer;

  @override
  String build() {
    ref.onDispose(() => _timer?.cancel());
    return '';
  }

  void set(String value) {
    _timer?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      state = '';
      return;
    }
    _timer = Timer(const Duration(milliseconds: 350), () {
      state = trimmed;
    });
  }
}

final debouncedCatalogQueryProvider =
    NotifierProvider<DebouncedCatalogQuery, String>(DebouncedCatalogQuery.new);

final recommendedModelsProvider = FutureProvider((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return FindModelsReply();
  }
  final filters = ref.watch(catalogFiltersProvider);
  ref.watch(daemonInfoProvider.select((async) {
    final bytes = async.value?.memoryAvailable.toInt() ?? 0;
    return bytes >> 30;
  }));
  return ref.watch(grpcClientProvider).findModels(
        limit: 8,
        minFit: filters.minFit,
        runtime: filters.runtime,
        recommendOnly: true,
      );
});

final catalogModelsProvider = FutureProvider((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return FindModelsReply();
  }
  final minFit = ref.watch(catalogFiltersProvider.select((f) => f.minFit));
  final runtime = ref.watch(catalogFiltersProvider.select((f) => f.runtime));
  final query = ref.watch(debouncedCatalogQueryProvider);
  ref.watch(daemonInfoProvider.select((async) {
    final bytes = async.value?.memoryAvailable.toInt() ?? 0;
    return bytes >> 30;
  }));
  return ref.watch(grpcClientProvider).findModels(
        limit: 200,
        minFit: minFit,
        runtime: runtime,
        query: query,
        includeTooTight: true,
        recommendOnly: false,
      );
});

final apiKeysProvider = FutureProvider((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return ListApiKeysReply();
  }
  return ref.watch(grpcClientProvider).listApiKeys();
});

enum ModelJobStatus { queued, running, done, error }

String modelDownloadRepo(ModelSuggestion model) => model.hfRepo;

class ModelDownloadJob {
  final String id;
  final String hfRepo;
  final String quant;
  final bool loadAfter;
  final ModelJobStatus status;
  final int percent;
  final String error;

  const ModelDownloadJob({
    required this.id,
    this.hfRepo = '',
    required this.quant,
    required this.loadAfter,
    this.status = ModelJobStatus.queued,
    this.percent = 0,
    this.error = '',
  });

  ModelDownloadJob copyWith({
    ModelJobStatus? status,
    int? percent,
    String? error,
  }) {
    return ModelDownloadJob(
      id: id,
      hfRepo: hfRepo,
      quant: quant,
      loadAfter: loadAfter,
      status: status ?? this.status,
      percent: percent ?? this.percent,
      error: error ?? this.error,
    );
  }
}

class ModelDownloadQueue extends Notifier<List<ModelDownloadJob>> {
  Future<void>? _pump;

  @override
  List<ModelDownloadJob> build() => const [];

  int get activeCount =>
      state.where((j) => j.status == ModelJobStatus.queued || j.status == ModelJobStatus.running).length;

  void enqueue(String id, String quant, {String hfRepo = '', bool loadAfter = false}) {
    final busy = state.any((j) =>
        j.id == id &&
        (j.status == ModelJobStatus.queued || j.status == ModelJobStatus.running));
    if (busy) return;
    state = [
      ...state.where((j) => j.id != id),
      ModelDownloadJob(id: id, hfRepo: hfRepo, quant: quant, loadAfter: loadAfter),
    ];
    _pump ??= _run();
  }

  void _patch(String id, ModelDownloadJob Function(ModelDownloadJob) update) {
    state = [
      for (final job in state)
        if (job.id == id) update(job) else job,
    ];
  }

  Future<void> _run() async {
    try {
      while (true) {
        final pending = state.where((j) => j.status == ModelJobStatus.queued).toList();
        if (pending.isEmpty) return;
        final job = pending.first;
        _patch(job.id, (j) => j.copyWith(status: ModelJobStatus.running));
        try {
          final client = ref.read(grpcClientProvider);
          await for (final reply in client.pullModel(job.id, quant: job.quant, hfRepo: job.hfRepo)) {
            final raw = int.tryParse(reply.launchProgress.percentComplete) ?? 0;
            _patch(job.id, (j) => j.copyWith(percent: raw.clamp(0, 100)));
          }
          if (job.loadAfter) {
            await client.loadModel(job.id, quant: job.quant).last;
            ref.invalidate(loadedModelsProvider);
          }
          _patch(job.id, (j) => j.copyWith(status: ModelJobStatus.done, percent: 100));
          ref.invalidate(loadedModelsProvider);
        } catch (e) {
          final message = e is GrpcError ? (e.message ?? '$e') : '$e';
          _patch(job.id, (j) => j.copyWith(status: ModelJobStatus.error, error: message));
        }
      }
    } finally {
      _pump = null;
      if (state.any((j) => j.status == ModelJobStatus.queued)) {
        _pump = _run();
      }
    }
  }
}

final modelDownloadQueueProvider =
    NotifierProvider<ModelDownloadQueue, List<ModelDownloadJob>>(
  ModelDownloadQueue.new,
);

class ModelsScreen extends ConsumerWidget {
  static const sidebarKey = 'models';
  static const openaiBaseUrl = 'https://127.0.0.1:7777/v1';

  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final activeDownloads = ref.watch(modelDownloadQueueProvider).where((j) =>
        j.status == ModelJobStatus.queued || j.status == ModelJobStatus.running).length;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: PageSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.modelsLabel,
                style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 12),
              TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: l10n.modelsTabCatalog),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.modelsTabDownloads),
                        if (activeDownloads > 0) ...[
                          const SizedBox(width: 8),
                          Badge(label: Text('$activeDownloads')),
                        ],
                      ],
                    ),
                  ),
                  Tab(text: l10n.modelsTabBackends),
                  Tab(text: l10n.modelsTabRuntimes),
                ],
              ),
              const SizedBox(height: 16),
              const Expanded(
                child: TabBarView(
                  children: [
                    _CatalogPane(),
                    _DownloadsPane(),
                    _BackendsPane(),
                    _RuntimesPane(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogPane extends ConsumerStatefulWidget {
  const _CatalogPane();

  @override
  ConsumerState<_CatalogPane> createState() => _CatalogPaneState();
}

class _CatalogPaneState extends ConsumerState<_CatalogPane> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filters = ref.watch(catalogFiltersProvider);
    final recommended = ref.watch(recommendedModelsProvider);
    final catalog = ref.watch(catalogModelsProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) {
            ref.read(catalogFiltersProvider.notifier).setSearch(value);
            ref.read(debouncedCatalogQueryProvider.notifier).set(value);
          },
          style: TextStyle(fontFamily: Brand.fontFamily, fontSize: 13, color: onSurface),
          decoration: InputDecoration(
            hintText: l10n.modelsSearchHint,
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.modelsFilterRuntime, style: const TextStyle(fontSize: 11)),
            ChoiceChip(
              label: Text(l10n.modelsFilterAny, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selected: filters.runtime.isEmpty,
              onSelected: (_) => ref.read(catalogFiltersProvider.notifier).setRuntime(''),
            ),
            ChoiceChip(
              label: Text(l10n.modelsRuntimeLlama, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selected: filters.runtime == 'llamacpp',
              onSelected: (_) =>
                  ref.read(catalogFiltersProvider.notifier).setRuntime('llamacpp'),
            ),
            ChoiceChip(
              label: Text(l10n.modelsRuntimeMlx, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selected: filters.runtime == 'mlx',
              onSelected: (_) => ref.read(catalogFiltersProvider.notifier).setRuntime('mlx'),
            ),
            const SizedBox(width: 6),
            Text(l10n.modelsFilterFit, style: const TextStyle(fontSize: 11)),
            ChoiceChip(
              label: Text(l10n.modelsFilterAny, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selected: filters.minFit.isEmpty,
              onSelected: (_) => ref.read(catalogFiltersProvider.notifier).setMinFit(''),
            ),
            ChoiceChip(
              label: Text(l10n.modelsFitPerfect, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selected: filters.minFit == 'perfect',
              onSelected: (_) =>
                  ref.read(catalogFiltersProvider.notifier).setMinFit('perfect'),
            ),
            ChoiceChip(
              label: Text(l10n.modelsFitGood, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selected: filters.minFit == 'good',
              onSelected: (_) => ref.read(catalogFiltersProvider.notifier).setMinFit('good'),
            ),
            ChoiceChip(
              label: Text(l10n.modelsFitMarginal, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selected: filters.minFit == 'marginal',
              onSelected: (_) =>
                  ref.read(catalogFiltersProvider.notifier).setMinFit('marginal'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        recommended.when(
          data: (reply) {
            if (reply.models.isEmpty) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.modelsSuggestedHeading, style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 4),
                SizedBox(
                  height: 28,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: reply.models.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (context, index) =>
                        _RecommendedChip(model: reply.models[index]),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        Expanded(
          child: catalog.when(
            data: (reply) {
              if (reply.replyMessage.isNotEmpty && reply.models.isEmpty) {
                return Text(reply.replyMessage);
              }
              if (reply.models.isEmpty) {
                return Text(l10n.modelsCatalogEmpty);
              }
              return _CatalogTable(models: reply.models);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
          ),
        ),
      ],
    );
  }
}

class _RecommendedChip extends ConsumerWidget {
  final ModelSuggestion model;
  const _RecommendedChip({required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = model.name.isEmpty ? model.id : model.name;
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      onPressed: () => ref.read(modelDownloadQueueProvider.notifier).enqueue(
            model.id,
            model.bestQuant,
            hfRepo: modelDownloadRepo(model),
            loadAfter: true,
          ),
    );
  }
}

class _CatalogTable extends ConsumerWidget {
  final List<ModelSuggestion> models;
  const _CatalogTable({required this.models});

  static Widget _header(String name) {
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  static Widget _cell(String text, {Color? color}) {
    return Text(
      text.isEmpty ? '-' : text,
      style: TextStyle(fontSize: 10, color: color),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  static String? _inferParamSize(String id) {
    final match = RegExp(r'(\d+(?:\.\d+)?)[Bb](?:\b|[-_]|$)').firstMatch(id);
    return match != null ? '${match.group(1)}B' : null;
  }

  static String _params(ModelSuggestion model) {
    if (model.parameterCount.isNotEmpty) return model.parameterCount;
    return _inferParamSize(model.id) ?? _inferParamSize(model.name) ?? '';
  }

  static String _disk(ModelSuggestion model) {
    if (model.diskSizeGb <= 0) return '';
    final gb = model.diskSizeGb;
    return gb >= 10 ? '${gb.toStringAsFixed(0)}G' : '${gb.toStringAsFixed(1)}G';
  }

  static String _ctx(ModelSuggestion model) {
    final tokens = model.usableContext.toInt() > 0
        ? model.usableContext.toInt()
        : model.contextLength.toInt();
    if (tokens <= 0) return '';
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(0)}k';
    return '$tokens';
  }

  static String _useCase(ModelSuggestion model) {
    if (model.category.isNotEmpty) return model.category;
    return model.useCase;
  }

  static Color? _fitColor(String fit, ColorScheme scheme) {
    final lower = fit.toLowerCase();
    if (lower.contains('perfect')) return Colors.green.shade400;
    if (lower.contains('good')) return Colors.lightGreen.shade400;
    if (lower.contains('marginal')) return Colors.orange.shade400;
    if (lower.contains('tight') || lower.contains('too')) return scheme.error;
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final headers = <vmtable.TableHeader<ModelSuggestion>>[
      vmtable.TableHeader(
        name: 'Model',
        childBuilder: _header,
        width: 380,
        minWidth: 280,
        sortKey: (m) => m.name.isEmpty ? m.id : m.name,
        cellBuilder: (m) {
          final label = m.name.isEmpty ? m.id : m.name;
          return Tooltip(message: label, child: _cell(label));
        },
      ),
      vmtable.TableHeader(
        name: 'Provider',
        childBuilder: _header,
        width: 100,
        minWidth: 72,
        sortKey: (m) => m.provider,
        cellBuilder: (m) => _cell(m.provider),
      ),
      vmtable.TableHeader(
        name: 'Params',
        childBuilder: _header,
        width: 64,
        minWidth: 48,
        sortKey: (m) => _params(m),
        cellBuilder: (m) => _cell(_params(m)),
      ),
      vmtable.TableHeader(
        name: 'Score',
        childBuilder: _header,
        width: 52,
        minWidth: 44,
        sortKey: (m) => m.score.toStringAsFixed(1).padLeft(8, '0'),
        cellBuilder: (m) => _cell(m.score > 0 ? m.score.round().toString() : ''),
      ),
      vmtable.TableHeader(
        name: 'tok/s',
        childBuilder: _header,
        width: 52,
        minWidth: 44,
        sortKey: (m) => m.estimatedTps.toStringAsFixed(1).padLeft(8, '0'),
        cellBuilder: (m) =>
            _cell(m.estimatedTps > 0 ? m.estimatedTps.toStringAsFixed(1) : ''),
      ),
      vmtable.TableHeader(
        name: 'Quant',
        childBuilder: _header,
        width: 80,
        minWidth: 56,
        sortKey: (m) => m.bestQuant,
        cellBuilder: (m) => _cell(m.bestQuant),
      ),
      vmtable.TableHeader(
        name: 'Disk',
        childBuilder: _header,
        width: 52,
        minWidth: 44,
        sortKey: (m) => m.diskSizeGb.toStringAsFixed(2).padLeft(8, '0'),
        cellBuilder: (m) => _cell(_disk(m)),
      ),
      vmtable.TableHeader(
        name: 'Mode',
        childBuilder: _header,
        width: 52,
        minWidth: 44,
        sortKey: (m) => m.runMode,
        cellBuilder: (m) => _cell(m.runMode),
      ),
      vmtable.TableHeader(
        name: 'Mem %',
        childBuilder: _header,
        width: 56,
        minWidth: 48,
        sortKey: (m) => m.utilizationPct.toStringAsFixed(1).padLeft(8, '0'),
        cellBuilder: (m) =>
            _cell(m.utilizationPct > 0 ? '${m.utilizationPct.round()}%' : ''),
      ),
      vmtable.TableHeader(
        name: 'Ctx',
        childBuilder: _header,
        width: 56,
        minWidth: 44,
        sortKey: (m) => _ctx(m).padLeft(8, '0'),
        cellBuilder: (m) => _cell(_ctx(m)),
      ),
      vmtable.TableHeader(
        name: 'Date',
        childBuilder: _header,
        width: 64,
        minWidth: 52,
        sortKey: (m) => m.releaseDate,
        cellBuilder: (m) => _cell(m.releaseDate),
      ),
      vmtable.TableHeader(
        name: 'Fit',
        childBuilder: _header,
        width: 72,
        minWidth: 56,
        sortKey: (m) => m.fitLevel,
        cellBuilder: (m) => _cell(m.fitLevel, color: _fitColor(m.fitLevel, scheme)),
      ),
      vmtable.TableHeader(
        name: 'Use Case',
        childBuilder: _header,
        width: 120,
        minWidth: 80,
        sortKey: (m) => _useCase(m),
        cellBuilder: (m) => _cell(_useCase(m)),
      ),
      vmtable.TableHeader(
        name: 'Actions',
        childBuilder: _header,
        width: 120,
        minWidth: 96,
        cellBuilder: (m) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CatalogAction(
              label: l10n.modelsDownload,
              color: scheme.primary,
              onTap: () => ref.read(modelDownloadQueueProvider.notifier).enqueue(
                    m.id,
                    m.bestQuant,
                    hfRepo: modelDownloadRepo(m),
                  ),
            ),
            _CatalogAction(
              label: l10n.modelsLoad,
              color: scheme.primary,
              onTap: () => ref.read(modelDownloadQueueProvider.notifier).enqueue(
                    m.id,
                    m.bestQuant,
                    hfRepo: modelDownloadRepo(m),
                    loadAfter: true,
                  ),
            ),
          ],
        ),
      ),
    ];

    return vmtable.Table<ModelSuggestion>(
      headers: headers,
      data: models,
      rowExtent: 28,
      cellMargin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      finalRow: List.generate(headers.length, (_) => const SizedBox.shrink()),
    );
  }
}

class _CatalogAction extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CatalogAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, color: color, height: 1.0),
        ),
      ),
    );
  }
}

class _DownloadsPane extends ConsumerWidget {
  const _DownloadsPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final jobs = ref.watch(modelDownloadQueueProvider);
    final cached = ref.watch(loadedModelsProvider);

    return ListView(
      children: [
        if (jobs.isEmpty) Text(l10n.modelsQueueEmpty),
        for (final job in jobs.reversed) _DownloadJobTile(job: job),
        const SizedBox(height: 24),
        Text(l10n.modelsCachedHeading, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        cached.when(
          data: (reply) {
            if (reply.cached.isEmpty) {
              return Text(l10n.modelsCachedEmpty);
            }
            return Column(
              children: [
                for (final model in reply.cached)
                  ListTile(
                    title: Text(model.name.isEmpty ? model.id : model.name),
                    subtitle: Text(
                      [
                        if (model.bestQuant.isNotEmpty) model.bestQuant,
                        if (model.hfRepo.isNotEmpty) model.hfRepo,
                        if (model.memoryRequiredGb > 0)
                          '${model.memoryRequiredGb.toStringAsFixed(1)} GiB',
                      ].join(' · '),
                    ),
                    trailing: TextButton(
                      onPressed: () => ref.read(modelDownloadQueueProvider.notifier).enqueue(
                            model.id,
                            model.bestQuant,
                            hfRepo: modelDownloadRepo(model),
                            loadAfter: true,
                          ),
                      child: Text(l10n.modelsLoadCached),
                    ),
                  ),
              ],
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
        ),
      ],
    );
  }
}

class _DownloadJobTile extends StatelessWidget {
  final ModelDownloadJob job;
  const _DownloadJobTile({required this.job});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = switch (job.status) {
      ModelJobStatus.queued => l10n.modelsJobQueued,
      ModelJobStatus.running => l10n.modelsJobRunning,
      ModelJobStatus.done => l10n.modelsJobDone,
      ModelJobStatus.error => l10n.modelsJobError,
    };
    return ListTile(
      title: Text(job.id),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(job.quant.isEmpty ? label : '$label · ${job.quant}'),
          if (job.status == ModelJobStatus.running) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: job.percent > 0 ? job.percent / 100 : null,
            ),
          ],
          if (job.error.isNotEmpty) Text(job.error),
        ],
      ),
      trailing: job.status == ModelJobStatus.running ? Text('${job.percent}%') : null,
    );
  }
}

class _BackendsPane extends ConsumerWidget {
  const _BackendsPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final backends = ref.watch(llmBackendsProvider);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.modelsBackendsHint, style: const TextStyle(fontSize: 14)),
            ),
            TextButton.icon(
              onPressed: () => ref.invalidate(llmBackendsProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.modelsBackendsRefresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        backends.when(
          data: (reply) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reply.selectedBackend.isNotEmpty) ...[
                  Text(
                    '${l10n.modelsBackendsSelected}: ${reply.selectedBackend}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final backend in reply.backends) _BackendRow(backend: backend, scheme: scheme),
              ],
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
        ),
      ],
    );
  }
}

class _BackendRow extends StatelessWidget {
  final LlmBackendInfo backend;
  final ColorScheme scheme;

  const _BackendRow({required this.backend, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final status = backend.status;
    final (icon, color, statusLabel) = switch (status) {
      'ready' => (Icons.check_circle, scheme.primary, l10n.modelsBackendStatusReady),
      'missing' => (Icons.error, scheme.error, l10n.modelsBackendStatusMissing),
      _ => (Icons.info_outline, scheme.onSurfaceVariant, l10n.modelsBackendStatusOptional),
    };

    final subtitle = [
      if (backend.detail.isNotEmpty) backend.detail,
      if (backend.binaryPath.isNotEmpty) backend.binaryPath,
      if (backend.installHint.isNotEmpty) backend.installHint,
    ].join('\n');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Row(
          children: [
            Expanded(child: Text(backend.name.isEmpty ? backend.id : backend.name)),
            if (backend.required)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Chip(
                  label: Text(l10n.modelsBackendsRequired, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            if (backend.active)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Chip(
                  label: Text(l10n.modelsBackendsActive, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: backend.status == 'missing' && backend.installHint.isNotEmpty
            ? Tooltip(
                message: l10n.modelsBackendsInstallSoon,
                child: TextButton(
                  onPressed: null,
                  child: Text(l10n.modelsBackendsInstall),
                ),
              )
            : Text(statusLabel, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _RuntimesPane extends ConsumerWidget {
  const _RuntimesPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final loaded = ref.watch(loadedModelsProvider);
    final keys = ref.watch(apiKeysProvider);

    return ListView(
      children: [
        Text(l10n.modelsOpenaiHint, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('${l10n.modelsBaseUrl}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            const Expanded(child: CopyableText(ModelsScreen.openaiBaseUrl)),
          ],
        ),
        const SizedBox(height: 16),
        const HostResourceGauges(),
        const SizedBox(height: 24),
        Text(l10n.modelsLoadedHeading, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        loaded.when(
          data: (reply) {
            if (reply.models.isEmpty) {
              return Text(l10n.modelsLoadedEmpty);
            }
            return Column(
              children: [
                for (final model in reply.models) _LoadedRow(model: model),
              ],
            );
          },
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
                final created = await ref.read(grpcClientProvider).createApiKey(label: 'gui');
                if (context.mounted) {
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
                }
                ref.invalidate(apiKeysProvider);
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
                        await ref.read(grpcClientProvider).revokeApiKey(key.id);
                        ref.invalidate(apiKeysProvider);
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
    );
  }
}

class _LoadedRow extends ConsumerWidget {
  final LoadedModelInfo model;
  const _LoadedRow({required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(model.openaiId),
      subtitle: Text('${model.backend} · ${model.state} · 127.0.0.1:${model.port}'),
      trailing: TextButton(
        onPressed: () async {
          await ref.read(grpcClientProvider).unloadModel(model.modelId);
          ref.invalidate(loadedModelsProvider);
        },
        child: Text(l10n.modelsUnload),
      ),
    );
  }
}

class HostResourceGauges extends ConsumerWidget {
  final bool compact;
  const HostResourceGauges({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final info = ref.watch(daemonInfoProvider);
    return info.when(
      data: (data) {
        final memory = data.memory.toInt();
        final reserved = data.memoryReserved.toInt();
        final claimed = data.memoryClaimed.toInt();
        final usedHost = data.memoryUsedHost.toInt();
        final capacity = memory > reserved ? memory - reserved : memory;
        final hostPct = memory == 0 ? 0 : (100 * usedHost / memory).round();
        final cpuPct = (data.cpuUsagePermille / 10).toStringAsFixed(0);
        final ramBar = MemoryUsage(
          used: '$claimed',
          total: '$capacity',
        );
        final cpuValue = data.cpus == 0 ? 0.0 : data.cpusClaimed / data.cpus;
        final cpuBar = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: cpuValue.isFinite ? cpuValue.clamp(0.0, 1.0) : 0,
              backgroundColor: MemoryUsage.backgroundColor,
              color: cpuValue < 0.8 ? MemoryUsage.normalColor : MemoryUsage.almostFullColor,
            ),
            const SizedBox(height: 2),
            Text(
              '${data.cpusClaimed} / ${data.cpus}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface),
            ),
          ],
        );
        final child = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.hostRamScheduler, style: const TextStyle(fontSize: 11)),
                  ramBar,
                  const SizedBox(height: 6),
                  Text(l10n.hostCpuScheduler, style: const TextStyle(fontSize: 11)),
                  cpuBar,
                ],
              )
            : Row(
                children: [
                  Expanded(child: ramBar),
                  const SizedBox(width: 16),
                  Expanded(child: cpuBar),
                ],
              );
        return Tooltip(
          message: l10n.hostPressureTooltip(hostPct.toString(), cpuPct),
          child: child,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
