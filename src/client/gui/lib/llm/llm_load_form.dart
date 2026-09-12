import '../grpc_client.dart';

const defaultLlmCtxSize = 8192;
const defaultLlmMaxTokens = 0;

class LlmLoadForm {
  LlmLoadForm({
    this.runtime = 'llamacpp',
    this.ctxSize = defaultLlmCtxSize,
    this.maxTokens = defaultLlmMaxTokens,
    this.gpuOffload = 'auto',
    this.customGpuLayers = 32,
    this.flashAttn = 'auto',
    this.cacheType = 'q8_0',
    this.fit = true,
    this.threads = 0,
    this.threadsBatch = 0,
    this.batchSize = 0,
    this.ubatchSize = 0,
    this.parallel = 1,
    this.cacheReuse = 256,
    this.keepInRam = false,
    this.moeOffload = 'auto',
    this.nCpuMoe,
  });

  String runtime;
  int ctxSize;
  int maxTokens;
  /// auto | all | cpu | custom
  String gpuOffload;
  int customGpuLayers;
  String flashAttn;
  String cacheType;
  bool fit;
  int threads;
  int threadsBatch;
  int batchSize;
  int ubatchSize;
  int parallel;
  int cacheReuse;
  bool keepInRam;
  String moeOffload;
  int? nCpuMoe;

  bool get isLlama => runtime != 'mlx';

  String get nGpuLayers => switch (gpuOffload) {
        'all' => 'all',
        'cpu' => '0',
        'custom' => '$customGpuLayers',
        _ => 'auto',
      };

  LlmLoadParams toProto() {
    final params = LlmLoadParams(
      ctxSize: ctxSize,
      maxTokens: maxTokens,
    );
    if (!isLlama) return params;
    params
      ..nGpuLayers = nGpuLayers
      ..flashAttn = flashAttn
      ..cacheTypeK = cacheType
      ..cacheTypeV = cacheType
      ..fit = fit
      ..parallel = parallel
      ..cacheReuse = cacheReuse
      ..moeOffload = moeOffload;
    if (threads > 0) params.threads = threads;
    if (threadsBatch > 0) params.threadsBatch = threadsBatch;
    if (batchSize > 0) params.batchSize = batchSize;
    if (ubatchSize > 0) params.ubatchSize = ubatchSize;
    if (keepInRam) params.loadMode = 'mmap+mlock';
    if (nCpuMoe != null && nCpuMoe! >= 0) params.nCpuMoe = nCpuMoe!;
    return params;
  }

  Map<String, dynamic> toJson() => {
        'runtime': runtime,
        'ctx_size': ctxSize,
        'max_tokens': maxTokens,
        'gpu_offload': gpuOffload,
        'custom_gpu_layers': customGpuLayers,
        'flash_attn': flashAttn,
        'cache_type': cacheType,
        'fit': fit,
        'threads': threads,
        'threads_batch': threadsBatch,
        'batch_size': batchSize,
        'ubatch_size': ubatchSize,
        'parallel': parallel,
        'cache_reuse': cacheReuse,
        'keep_in_ram': keepInRam,
        'moe_offload': moeOffload,
        if (nCpuMoe != null) 'n_cpu_moe': nCpuMoe,
      };

  static LlmLoadForm fromJson(Map<String, dynamic>? json, {int? suggestedCtx}) {
    final form = LlmLoadForm(ctxSize: suggestedCtx ?? defaultLlmCtxSize);
    if (json == null) return form;
    form.runtime = json['runtime'] as String? ?? form.runtime;
    form.ctxSize = (json['ctx_size'] as num?)?.toInt() ?? form.ctxSize;
    form.maxTokens = (json['max_tokens'] as num?)?.toInt() ?? form.maxTokens;
    form.gpuOffload = json['gpu_offload'] as String? ?? form.gpuOffload;
    form.customGpuLayers =
        (json['custom_gpu_layers'] as num?)?.toInt() ?? form.customGpuLayers;
    form.flashAttn = json['flash_attn'] as String? ?? form.flashAttn;
    form.cacheType = json['cache_type'] as String? ?? form.cacheType;
    form.fit = json['fit'] as bool? ?? form.fit;
    form.threads = (json['threads'] as num?)?.toInt() ?? form.threads;
    form.threadsBatch =
        (json['threads_batch'] as num?)?.toInt() ?? form.threadsBatch;
    form.batchSize = (json['batch_size'] as num?)?.toInt() ?? form.batchSize;
    form.ubatchSize = (json['ubatch_size'] as num?)?.toInt() ?? form.ubatchSize;
    form.parallel = (json['parallel'] as num?)?.toInt() ?? form.parallel;
    form.cacheReuse = (json['cache_reuse'] as num?)?.toInt() ?? form.cacheReuse;
    form.keepInRam = json['keep_in_ram'] as bool? ?? form.keepInRam;
    form.moeOffload = json['moe_offload'] as String? ?? form.moeOffload;
    form.nCpuMoe = (json['n_cpu_moe'] as num?)?.toInt();
    return form;
  }

  bool get isValid =>
      ctxSize > 0 &&
      maxTokens >= 0 &&
      parallel > 0 &&
      cacheReuse >= 0 &&
      threads >= 0 &&
      threadsBatch >= 0 &&
      batchSize >= 0 &&
      ubatchSize >= 0 &&
      customGpuLayers >= 0 &&
      (nCpuMoe == null || nCpuMoe! >= 0);
}
