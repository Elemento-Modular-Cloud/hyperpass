import 'package:elp_gui/llm/llm_features.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inference allowlist includes llama, mlx, and vllm', () {
    expect(inferenceBackendIds, contains('llamacpp'));
    expect(inferenceBackendIds, contains('vllm'));
    expect(enableMlxBackend, isTrue);
    expect(inferenceBackendIds, contains('mlx'));
    expect(isLlamaRuntime('llamacpp-metal'), isTrue);
    expect(isVllmRuntime('vllm'), isTrue);
    expect(isMlxRuntime('mlx'), isTrue);
  });

  test('readyInferenceRuntimeIds keeps only probe-ready inference backends', () {
    final ready = readyInferenceRuntimeIds([
      (id: 'llmfit', status: 'ready'),
      (id: 'llamacpp', status: 'ready'),
      (id: 'vllm', status: 'missing'),
      (id: 'llamacpp-cuda', status: 'ready'),
      (id: 'mlx', status: 'ready'),
    ]);
    expect(ready, {'llamacpp', 'mlx'});
    expect(ready, isNot(contains('vllm')));
    expect(ready, isNot(contains('llmfit')));
    expect(ready, isNot(contains('llamacpp-cuda')));
  });
}
