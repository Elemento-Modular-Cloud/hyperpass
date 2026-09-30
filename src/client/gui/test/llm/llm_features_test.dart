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
}
