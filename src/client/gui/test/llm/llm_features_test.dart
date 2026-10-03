import 'package:elp_gui/llm/llm_features.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compatibleInferenceRuntimes maps format to a single family', () {
    expect(compatibleInferenceRuntimes(format: 'mlx'), {'mlx'});
    expect(compatibleInferenceRuntimes(format: 'gguf'), {'llamacpp'});
    expect(compatibleInferenceRuntimes(format: 'hf'), {'vllm'});
  });

  test('compatibleInferenceRuntimes prefers advertised runtimes', () {
    expect(
      compatibleInferenceRuntimes(
        format: 'gguf',
        supportedRuntimes: const ['mlx'],
      ),
      {'mlx'},
    );
    expect(
      compatibleInferenceRuntimes(
        format: 'mlx',
        supportedRuntimes: const ['llamacpp', 'cuda'],
      ),
      {'llamacpp'},
    );
  });

  test('compatibleInferenceRuntimes ignores unknown advertised ids', () {
    expect(
      compatibleInferenceRuntimes(
        format: 'gguf',
        supportedRuntimes: const ['cuda', 'metal'],
      ),
      {'llamacpp'},
    );
  });

  test('union of per-artifact runtimes covers gguf plus safetensors', () {
    expect(
      {
        ...compatibleInferenceRuntimes(format: 'gguf'),
        ...compatibleInferenceRuntimes(format: 'hf'),
      },
      {'llamacpp', 'vllm'},
    );
    expect(
      {
        ...compatibleInferenceRuntimes(format: 'gguf'),
        ...compatibleInferenceRuntimes(format: 'mlx'),
      },
      {'llamacpp', 'mlx'},
    );
  });

  test('inferVaultFormat treats directories as mlx and files as gguf', () {
    expect(inferVaultFormat(path: '/vault/model.gguf'), 'gguf');
    expect(inferVaultFormat(path: '/vault/mlx-community_Gemma-2-2B-it-4bit'), 'mlx');
    expect(inferVaultFormat(format: 'hf', path: '/vault/model'), 'hf');
  });
}
