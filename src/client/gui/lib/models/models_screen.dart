import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';

import '../brand.dart';
import '../copyable_text.dart';
import '../l10n/app_localizations.dart';
import '../page_surface.dart';
import '../providers.dart';
import '../tooltip.dart';
import '../vm_details/memory_usage.dart';

final loadedModelsProvider = FutureProvider((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return ListModelsReply();
  }
  return ref.watch(grpcClientProvider).listModels();
});

class CatalogFilters {
  final String search;
  final String useCase;
  final String minFit;
  final String runtime;

  const CatalogFilters({
    this.search = '',
    this.useCase = 'coding',
    this.minFit = '',
    this.runtime = '',
  });

  CatalogFilters copyWith({
    String? search,
    String? useCase,
    String? minFit,
    String? runtime,
  }) {
    return CatalogFilters(
      search: search ?? this.search,
      useCase: useCase ?? this.useCase,
      minFit: minFit ?? this.minFit,
      runtime: runtime ?? this.runtime,
    );
  }
}

class CatalogFiltersNotifier extends Notifier<CatalogFilters> {
  @override
  CatalogFilters build() => const CatalogFilters();

  void setSearch(String value) => state = state.copyWith(search: value);
  void setUseCase(String value) => state = state.copyWith(useCase: value);
  void setMinFit(String value) => state = state.copyWith(minFit: value);
  void setRuntime(String value) => state = state.copyWith(runtime: value);
}

final catalogFiltersProvider =
    NotifierProvider<CatalogFiltersNotifier, CatalogFilters>(
  CatalogFiltersNotifier.new,
);

final suggestedModelsProvider = FutureProvider((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return FindModelsReply();
  }
  final filters = ref.watch(catalogFiltersProvider);
  ref.watch(daemonInfoProvider.select((async) {
    final bytes = async.value?.memoryAvailable.toInt() ?? 0;
    return bytes >> 30;
  }));
  return ref.watch(grpcClientProvider).findModels(
        limit: 40,
        useCase: filters.useCase,
        minFit: filters.minFit,
        runtime: filters.runtime,
      );
});

final apiKeysProvider = FutureProvider((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return ListApiKeysReply();
  }
  return ref.watch(grpcClientProvider).listApiKeys();
});

enum ModelJobStatus { queued, running, done, error }

class ModelDownloadJob {
  final String id;
  final String quant;
  final bool loadAfter;
  final ModelJobStatus status;
  final int percent;
  final String error;

  const ModelDownloadJob({
    required this.id,
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

  void enqueue(String id, String quant, {bool loadAfter = false}) {
    final busy = state.any((j) =>
        j.id == id &&
        (j.status == ModelJobStatus.queued || j.status == ModelJobStatus.running));
    if (busy) return;
    state = [
      ...state.where((j) => j.id != id),
      ModelDownloadJob(id: id, quant: quant, loadAfter: loadAfter),
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
          await for (final reply in client.pullModel(job.id, quant: job.quant)) {
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
      length: 3,
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
                  Tab(text: l10n.modelsTabRuntimes),
                ],
              ),
              const SizedBox(height: 16),
              const Expanded(
                child: TabBarView(
                  children: [
                    _CatalogPane(),
                    _DownloadsPane(),
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
    final suggested = ref.watch(suggestedModelsProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) => ref.read(catalogFiltersProvider.notifier).setSearch(value),
          style: TextStyle(fontFamily: Brand.fontFamily, fontSize: 13, color: onSurface),
          decoration: InputDecoration(
            hintText: l10n.modelsSearchHint,
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.modelsFilterUseCase, style: const TextStyle(fontSize: 12)),
            for (final option in [
              (value: '', label: l10n.modelsFilterAny),
              (value: 'coding', label: l10n.modelsUseCaseCoding),
              (value: 'chat', label: l10n.modelsUseCaseChat),
              (value: 'reasoning', label: l10n.modelsUseCaseReasoning),
              (value: 'general', label: l10n.modelsUseCaseGeneral),
            ])
              ChoiceChip(
                label: Text(option.label),
                selected: filters.useCase == option.value,
                onSelected: (_) =>
                    ref.read(catalogFiltersProvider.notifier).setUseCase(option.value),
              ),
            const SizedBox(width: 8),
            Text(l10n.modelsFilterRuntime, style: const TextStyle(fontSize: 12)),
            ChoiceChip(
              label: Text(l10n.modelsFilterAny),
              selected: filters.runtime.isEmpty,
              onSelected: (_) => ref.read(catalogFiltersProvider.notifier).setRuntime(''),
            ),
            ChoiceChip(
              label: Text(l10n.modelsRuntimeLlama),
              selected: filters.runtime == 'llamacpp',
              onSelected: (_) =>
                  ref.read(catalogFiltersProvider.notifier).setRuntime('llamacpp'),
            ),
            ChoiceChip(
              label: Text(l10n.modelsRuntimeMlx),
              selected: filters.runtime == 'mlx',
              onSelected: (_) => ref.read(catalogFiltersProvider.notifier).setRuntime('mlx'),
            ),
            const SizedBox(width: 8),
            Text(l10n.modelsFilterFit, style: const TextStyle(fontSize: 12)),
            ChoiceChip(
              label: Text(l10n.modelsFilterAny),
              selected: filters.minFit.isEmpty,
              onSelected: (_) => ref.read(catalogFiltersProvider.notifier).setMinFit(''),
            ),
            ChoiceChip(
              label: Text(l10n.modelsFitPerfect),
              selected: filters.minFit == 'perfect',
              onSelected: (_) =>
                  ref.read(catalogFiltersProvider.notifier).setMinFit('perfect'),
            ),
            ChoiceChip(
              label: Text(l10n.modelsFitGood),
              selected: filters.minFit == 'good',
              onSelected: (_) => ref.read(catalogFiltersProvider.notifier).setMinFit('good'),
            ),
            ChoiceChip(
              label: Text(l10n.modelsFitMarginal),
              selected: filters.minFit == 'marginal',
              onSelected: (_) =>
                  ref.read(catalogFiltersProvider.notifier).setMinFit('marginal'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: suggested.when(
            data: (reply) {
              if (reply.replyMessage.isNotEmpty && reply.models.isEmpty) {
                return Text(reply.replyMessage);
              }
              final query = filters.search.trim().toLowerCase();
              final models = reply.models.where((model) {
                if (query.isEmpty) return true;
                return model.name.toLowerCase().contains(query) ||
                    model.provider.toLowerCase().contains(query) ||
                    model.id.toLowerCase().contains(query);
              }).toList();
              if (models.isEmpty) {
                return Text(l10n.modelsSuggestedEmpty);
              }
              return ListView.builder(
                itemCount: models.length,
                itemBuilder: (context, index) => _CatalogRow(model: models[index]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
          ),
        ),
      ],
    );
  }
}

class _CatalogRow extends ConsumerWidget {
  final ModelSuggestion model;
  const _CatalogRow({required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(model.name),
      subtitle: Text(
        '${model.fitLevel} · ${model.bestQuant} · ${model.memoryRequiredGb.toStringAsFixed(1)} GiB · ${model.runtime}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => ref.read(modelDownloadQueueProvider.notifier).enqueue(
                  model.id,
                  model.bestQuant,
                ),
            child: Text(l10n.modelsDownload),
          ),
          TextButton(
            onPressed: () => ref.read(modelDownloadQueueProvider.notifier).enqueue(
                  model.id,
                  model.bestQuant,
                  loadAfter: true,
                ),
            child: Text(l10n.modelsLoad),
          ),
        ],
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
