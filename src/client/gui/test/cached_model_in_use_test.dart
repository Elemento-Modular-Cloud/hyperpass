import 'package:elp_gui/grpc_client.dart';
import 'package:elp_gui/llm/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loaded model id blocks deletion', () {
    final model = ModelSuggestion()
      ..id = 'Llama-3.2-3B'
      ..path = '/vault/llama.gguf';
    final loaded = [
      LoadedModelInfo()
        ..modelId = 'Llama-3.2-3B'
        ..path = '/vault/llama.gguf',
    ];
    expect(isCachedModelInUse(model, loaded), isTrue);
  });

  test('idle cached model can be deleted', () {
    final model = ModelSuggestion()
      ..id = 'Gemma-2-2B'
      ..path = '/vault/gemma.gguf';
    final loaded = [
      LoadedModelInfo()
        ..modelId = 'Llama-3.2-3B'
        ..path = '/vault/llama.gguf',
    ];
    expect(isCachedModelInUse(model, loaded), isFalse);
  });

  test('path match still counts as in use', () {
    final model = ModelSuggestion()
      ..id = 'alias'
      ..path = '/vault/llama.gguf';
    final loaded = [
      LoadedModelInfo()
        ..modelId = 'Llama-3.2-3B'
        ..path = '/vault/llama.gguf',
    ];
    expect(isCachedModelInUse(model, loaded), isTrue);
  });

  test('pending load placeholder is starting', () {
    const pending = PendingLlmLoad(
      id: 'pending-load-1',
      modelId: 'Gemma-2-9B',
      runtime: 'llamacpp',
      ctxSize: 8192,
      maxTokens: 0,
    );
    expect(isPendingLlmLoad(pending.placeholder), isTrue);
    expect(pending.placeholder.state, pendingLlmLoadState);
    expect(pending.placeholder.modelId, 'Gemma-2-9B');
  });

  test('pending load counts as in use', () {
    final model = ModelSuggestion()..id = 'Gemma-2-9B';
    const pending = PendingLlmLoad(
      id: 'pending-load-1',
      modelId: 'Gemma-2-9B',
      runtime: 'llamacpp',
      ctxSize: 8192,
      maxTokens: 0,
    );
    expect(
      isCachedModelInUse(model, const [], pendingLoads: [pending]),
      isTrue,
    );
  });
}
