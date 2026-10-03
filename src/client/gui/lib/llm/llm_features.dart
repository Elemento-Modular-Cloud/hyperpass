/// Kill-switch for MLX inference/catalog UI (paired with `enable_mlx_backend` in constants.h).
const enableMlxBackend = true;

/// Inference runners the GUI may deploy (filtered further by probe `ready` status).
const inferenceBackendIds = {
  'llamacpp',
  if (enableMlxBackend) 'mlx',
  'vllm',
};

bool isInferenceBackendId(String id) => inferenceBackendIds.contains(id);

bool isLlamaRuntime(String runtime) =>
    runtime == 'llamacpp' || runtime.startsWith('llamacpp-');

bool isMlxRuntime(String runtime) => runtime == 'mlx';

bool isVllmRuntime(String runtime) => runtime == 'vllm';

/// Vault / pull format for an inference runtime id.
String formatForRuntime(String runtime) {
  if (isMlxRuntime(runtime)) return 'mlx';
  if (isVllmRuntime(runtime)) return 'hf';
  return 'gguf';
}

/// Best-effort format when the vault row omitted [format].
String inferVaultFormat({
  String format = '',
  String path = '',
  String filename = '',
}) {
  final raw = format.trim().toLowerCase();
  if (raw.isNotEmpty) return raw;
  final p = path.trim();
  if (p.toLowerCase().endsWith('.gguf')) return 'gguf';
  if (filename.trim().toLowerCase().endsWith('.gguf')) return 'gguf';
  // Local MLX/HF snapshots are directories, often absolute, without .gguf.
  if (p.isNotEmpty) return 'mlx';
  return 'gguf';
}

/// Runtimes that can serve a model of [format], optionally constrained by the
/// catalog/vault [supportedRuntimes] list. MLX weights never map to llama.cpp
/// and GGUF never maps to MLX.
Set<String> compatibleInferenceRuntimes({
  String format = '',
  Iterable<String> supportedRuntimes = const [],
}) {
  final advertised = {
    for (final id in supportedRuntimes)
      if (isInferenceBackendId(id)) id,
  };
  if (advertised.isNotEmpty) return advertised;

  switch (format.trim().toLowerCase()) {
    case 'mlx':
      return {if (enableMlxBackend) 'mlx'};
    case 'hf':
      return {'vllm'};
    case 'gguf':
      return {'llamacpp'};
    default:
      return {...inferenceBackendIds};
  }
}
