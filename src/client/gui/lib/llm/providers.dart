import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/download_manager.dart';
import '../overview/recent_activity.dart';
import '../providers.dart';
import '../sidebar.dart';
import 'catalogue/top_picks.dart';
import 'instances/llm_downloaded_screen.dart';
import 'llm_features.dart';
import 'llm_id.dart';

String effectiveCatalogRuntime(String runtime) {
  if (!enableMlxBackend && runtime == 'mlx') return '';
  return runtime;
}

/// Live list of loaded instances and cached GGUFs.
///
/// A one-shot [FutureProvider] stayed on the last successful reply after
/// unload, so the Running table kept a ghost row until the GUI restarted.
/// Poll like the VM info stream so the UI converges on daemon state.
final loadedModelsProvider = StreamProvider<ListModelsReply>((ref) async* {
  if (!ref.watch(daemonAvailableProvider)) {
    yield ListModelsReply();
    return;
  }

  final client = ref.watch(grpcClientProvider);
  while (true) {
    final timer = Future.delayed(const Duration(milliseconds: 1900));
    try {
      yield await client.listModels();
    } catch (_) {
      // Keep the last successful list; the next poll will recover.
    }
    await timer;
  }
});

final llmBackendsProvider = FutureProvider((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return ListLlmBackendsReply();
  }
  return ref.watch(grpcClientProvider).listLlmBackends();
});

class LlmBackendInstalls extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    return {
      for (final job in ref.watch(downloadManagerProvider))
        if (job.kind == DownloadKind.llmRuntime && job.isActive)
          job.modelId: job.percent,
    };
  }

  Future<void> install(String backendId) async {
    ref.read(downloadManagerProvider.notifier).enqueue(
      kind: DownloadKind.llmRuntime,
      label: backendId,
      dedupKey: 'runtime:$backendId',
      modelId: backendId,
      execute: (controller) async {
        final client = ref.read(grpcClientProvider);
        await for (final reply in client.installLlmBackend(backendId)) {
          if (controller.isCancelled) break;
          controller.setPercent(reply.progressPercent);
          if (reply.status == 'ready' || reply.status == 'error') break;
        }
        ref.invalidate(llmBackendsProvider);
      },
    );
  }
}

final llmBackendInstallsProvider =
    NotifierProvider<LlmBackendInstalls, Map<String, int>>(LlmBackendInstalls.new);

/// Instance IDs whose unload RPC has been sent but is not yet reflected in
/// [loadedModelsProvider]. The Running table and sidebar badge filter these
/// out immediately so a ghost row cannot linger until the next poll.
class PendingLlmUnloads extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.listen(loadedModelsProvider, (_, next) {
      final live = next.asData?.value.models.map((m) => m.instanceId).toSet();
      if (live == null || state.isEmpty) return;
      final leftover = state.intersection(live);
      if (leftover.length != state.length) {
        state = leftover;
      }
    });
    return const {};
  }

  void add(String instanceId) => state = {...state, instanceId};

  void remove(String instanceId) {
    if (!state.contains(instanceId)) return;
    state = {...state}..remove(instanceId);
  }
}

final pendingLlmUnloadsProvider =
    NotifierProvider<PendingLlmUnloads, Set<String>>(PendingLlmUnloads.new);

class PendingLlmLoad {
  const PendingLlmLoad({
    required this.id,
    required this.modelId,
    required this.runtime,
    required this.ctxSize,
    required this.maxTokens,
  });

  final String id;
  final String modelId;
  final String runtime;
  final int ctxSize;
  final int maxTokens;

  LoadedModelInfo get placeholder => LoadedModelInfo(
        instanceId: id,
        modelId: modelId,
        backend: runtime,
        state: pendingLlmLoadState,
        ctxSize: ctxSize,
        maxTokens: maxTokens,
      );
}

const pendingLlmLoadState = 'starting';
const pendingLlmLoadIdPrefix = 'pending-load-';

bool isPendingLlmLoad(LoadedModelInfo model) =>
    model.state == pendingLlmLoadState ||
    model.instanceId.startsWith(pendingLlmLoadIdPrefix);

class PendingLlmLoads extends Notifier<List<PendingLlmLoad>> {
  @override
  List<PendingLlmLoad> build() => const [];

  void add(PendingLlmLoad load) => state = [...state, load];

  void remove(String id) {
    if (!state.any((load) => load.id == id)) return;
    state = [for (final load in state) if (load.id != id) load];
  }
}

final pendingLlmLoadsProvider =
    NotifierProvider<PendingLlmLoads, List<PendingLlmLoad>>(PendingLlmLoads.new);

Future<void> unloadLlmInstance(String instanceId) async {
  // Use the app-wide container so post-await updates stay safe after the
  // running-models list rebuilds / unmounts the widget that started unload.
  final pending = providerContainer.read(pendingLlmUnloadsProvider.notifier);
  pending.add(instanceId);
  try {
    await providerContainer.read(grpcClientProvider).unloadModel(instanceId);
    providerContainer.invalidate(loadedModelsProvider);
    providerContainer.read(recentActivityProvider.notifier).record(
          title: 'Unloaded model',
          detail: instanceId,
        );
  } catch (_) {
    providerContainer.read(pendingLlmUnloadsProvider.notifier).remove(instanceId);
    rethrow;
  }
}

final loadedLlmIdsProvider = Provider<List<LlmInstanceId>>((ref) {
  final loaded = ref.watch(loadedModelsProvider);
  final pending = ref.watch(pendingLlmUnloadsProvider);
  return loaded.when(
    data: (reply) => reply.models
        .where((m) => !pending.contains(m.instanceId))
        .map((m) => LlmInstanceId(instanceId: m.instanceId, modelId: m.modelId))
        .toList(growable: false),
    loading: () => const [],
    error: (_, __) => const [],
  );
});

/// True when a cached GGUF is currently loaded for inference.
bool isCachedModelInUse(
  ModelSuggestion model,
  Iterable<LoadedModelInfo> loaded, {
  Iterable<PendingLlmLoad> pendingLoads = const [],
}) {
  if (pendingLoads.any((load) => load.modelId == model.id)) return true;
  for (final instance in loaded) {
    if (instance.modelId == model.id) return true;
    if (model.path.isNotEmpty &&
        instance.path.isNotEmpty &&
        instance.path == model.path) {
      return true;
    }
  }
  return false;
}

/// On-disk size for a vault entry. Cached list_models rows store file size in
/// [ModelSuggestion.memoryRequiredGb]; catalog rows use [diskSizeGb].
int cachedModelDiskBytes(ModelSuggestion model) {
  final gb = model.diskSizeGb > 0 ? model.diskSizeGb : model.memoryRequiredGb;
  if (gb <= 0) return 0;
  return (gb * 1024 * 1024 * 1024).round();
}

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
        runtime: effectiveCatalogRuntime(filters.runtime),
        recommendOnly: true,
      );
});

/// Simple-mode catalog: curated picks enriched with llmfit recommend + fit.
final topPicksModelsProvider = FutureProvider<List<ModelSuggestion>>((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return [
      for (final pick in kCuratedTopPicks) stubFromCurated(pick),
    ].take(kTopPicksTargetCount).toList();
  }

  ref.watch(daemonInfoProvider.select((async) {
    final bytes = async.value?.memoryAvailable.toInt() ?? 0;
    return bytes >> 30;
  }));

  final client = ref.watch(grpcClientProvider);
  final runtime = effectiveCatalogRuntime(
    ref.watch(catalogFiltersProvider.select((f) => f.runtime)),
  );

  final results = await Future.wait([
    client.findModels(
      limit: 24,
      minFit: 'good',
      runtime: runtime,
      recommendOnly: true,
    ),
    client.findModels(
      limit: 80,
      minFit: 'marginal',
      runtime: runtime,
      includeTooTight: false,
      recommendOnly: false,
    ),
  ]);

  return mergeTopPicks(
    recommended: results[0].models,
    fitted: results[1].models,
  );
});

class CatalogAdvancedMode extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;

  void toggle() => state = !state;
}

final catalogAdvancedModeProvider =
    NotifierProvider<CatalogAdvancedMode, bool>(CatalogAdvancedMode.new);

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
        runtime: effectiveCatalogRuntime(runtime),
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
  final String jobKey;
  final String modelId;
  final String hfRepo;
  final String quant;
  final ModelJobStatus status;
  final int percent;
  final String error;
  final String path;

  const ModelDownloadJob({
    required this.jobKey,
    required this.modelId,
    this.hfRepo = '',
    required this.quant,
    this.status = ModelJobStatus.queued,
    this.percent = 0,
    this.error = '',
    this.path = '',
  });

  ModelDownloadJob copyWith({
    ModelJobStatus? status,
    int? percent,
    String? error,
    String? path,
  }) {
    return ModelDownloadJob(
      jobKey: jobKey,
      modelId: modelId,
      hfRepo: hfRepo,
      quant: quant,
      status: status ?? this.status,
      percent: percent ?? this.percent,
      error: error ?? this.error,
      path: path ?? this.path,
    );
  }
}

class ModelDownloadQueue extends Notifier<List<ModelDownloadJob>> {
  @override
  List<ModelDownloadJob> build() {
    return [
      for (final job in ref.watch(downloadManagerProvider))
        if (job.kind == DownloadKind.llmModel)
          ModelDownloadJob(
            jobKey: job.id,
            modelId: job.modelId,
            hfRepo: job.hfRepo,
            quant: job.quant,
            status: switch (job.status) {
              DownloadStatus.queued => ModelJobStatus.queued,
              DownloadStatus.running => ModelJobStatus.running,
              DownloadStatus.done => ModelJobStatus.done,
              DownloadStatus.error ||
              DownloadStatus.cancelled =>
                ModelJobStatus.error,
            },
            percent: job.percent,
            error: job.error,
            path: job.path,
          ),
    ];
  }

  int get activeCount =>
      state.where((j) => j.status == ModelJobStatus.queued || j.status == ModelJobStatus.running).length;

  void enqueueDownload(String modelId, String quant, {String hfRepo = ''}) {
    ref.read(downloadManagerProvider.notifier).enqueue(
      kind: DownloadKind.llmModel,
      label: modelId,
      dedupKey: 'llm:$modelId',
      modelId: modelId,
      quant: quant,
      hfRepo: hfRepo,
      execute: (controller) async {
        final client = ref.read(grpcClientProvider);
        var savedPath = '';
        await for (final reply in client.pullModel(
          modelId,
          quant: quant,
          hfRepo: hfRepo,
        )) {
          if (controller.isCancelled) break;
          final raw = int.tryParse(reply.launchProgress.percentComplete) ?? 0;
          if (reply.path.isNotEmpty) savedPath = reply.path;
          controller.setPercent(raw);
          if (savedPath.isNotEmpty) controller.setPath(savedPath);
        }
        ref.invalidate(loadedModelsProvider);
      },
    );
    ref.read(sidebarKeyProvider.notifier).set(LlmDownloadedScreen.sidebarKey);
  }
}

final modelDownloadQueueProvider =
    NotifierProvider<ModelDownloadQueue, List<ModelDownloadJob>>(
  ModelDownloadQueue.new,
);
