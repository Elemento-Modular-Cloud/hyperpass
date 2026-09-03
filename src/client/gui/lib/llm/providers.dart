import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';

import '../providers.dart';
import '../sidebar.dart';
import 'llm_id.dart';

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

Future<void> unloadLlmInstance(WidgetRef ref, String instanceId) async {
  ref.read(pendingLlmUnloadsProvider.notifier).add(instanceId);
  try {
    await ref.read(grpcClientProvider).unloadModel(instanceId);
    ref.invalidate(loadedModelsProvider);
  } catch (_) {
    ref.read(pendingLlmUnloadsProvider.notifier).remove(instanceId);
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

class MyModelsTabIndex extends Notifier<int> {
  @override
  int build() => 0;

  void setRunning() => state = 0;
  void setDownloaded() => state = 1;
  void set(int index) => state = index;
}

final myModelsTabProvider = NotifierProvider<MyModelsTabIndex, int>(MyModelsTabIndex.new);

class ModelDownloadQueue extends Notifier<List<ModelDownloadJob>> {
  Future<void>? _pump;

  @override
  List<ModelDownloadJob> build() => const [];

  int get activeCount =>
      state.where((j) => j.status == ModelJobStatus.queued || j.status == ModelJobStatus.running).length;

  void enqueueDownload(String modelId, String quant, {String hfRepo = ''}) {
    final busy = state.any((j) =>
        j.modelId == modelId &&
        (j.status == ModelJobStatus.queued || j.status == ModelJobStatus.running));
    if (busy) return;

    final jobKey = '${modelId}_${DateTime.now().microsecondsSinceEpoch}';
    state = [
      ...state.where((j) => j.modelId != modelId || j.status == ModelJobStatus.error),
      ModelDownloadJob(
        jobKey: jobKey,
        modelId: modelId,
        hfRepo: hfRepo,
        quant: quant,
      ),
    ];
    ref.read(myModelsTabProvider.notifier).setDownloaded();
    ref.read(sidebarKeyProvider.notifier).set('llm-instances');
    _pump ??= _run();
  }

  void _patch(String jobKey, ModelDownloadJob Function(ModelDownloadJob) update) {
    state = [
      for (final job in state)
        if (job.jobKey == jobKey) update(job) else job,
    ];
  }

  Future<void> _run() async {
    try {
      while (true) {
        final pending = state.where((j) => j.status == ModelJobStatus.queued).toList();
        if (pending.isEmpty) return;
        final job = pending.first;
        _patch(job.jobKey, (j) => j.copyWith(status: ModelJobStatus.running));
        try {
          final client = ref.read(grpcClientProvider);
          var savedPath = '';
          await for (final reply in client.pullModel(job.modelId, quant: job.quant, hfRepo: job.hfRepo)) {
            final raw = int.tryParse(reply.launchProgress.percentComplete) ?? 0;
            if (reply.path.isNotEmpty) savedPath = reply.path;
            _patch(job.jobKey, (j) => j.copyWith(percent: raw.clamp(0, 100), path: savedPath));
          }
          _patch(job.jobKey, (j) => j.copyWith(status: ModelJobStatus.done, percent: 100, path: savedPath));
          ref.invalidate(loadedModelsProvider);
        } catch (e) {
          final message = e is GrpcError ? (e.message ?? '$e') : '$e';
          _patch(job.jobKey, (j) => j.copyWith(status: ModelJobStatus.error, error: message));
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
