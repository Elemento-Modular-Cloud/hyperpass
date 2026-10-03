import 'package:elp_gui/grpc_client.dart';
import 'package:elp_gui/llm/my_models_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groupCachedModels merges artifacts with the same id', () {
    final models = [
      ModelSuggestion()
        ..id = 'deepseek-ai/DeepSeek-R1-Distill-Qwen-7B'
        ..name = 'deepseek-ai/DeepSeek-R1-Distill-Qwen-7B'
        ..format = 'gguf'
        ..bestQuant = 'Q4_K_M'
        ..diskSizeGb = 4.4
        ..path = '/tmp/vault/model.gguf',
      ModelSuggestion()
        ..id = 'deepseek-ai/DeepSeek-R1-Distill-Qwen-7B'
        ..name = 'deepseek-ai/DeepSeek-R1-Distill-Qwen-7B'
        ..format = 'mlx'
        ..bestQuant = 'mlx-8bit'
        ..diskSizeGb = 4.4
        ..path = 'deepseek-ai/DeepSeek-R1-Distill-Qwen-7B',
      ModelSuggestion()
        ..id = 'other/model'
        ..name = 'other/model'
        ..format = 'gguf'
        ..bestQuant = 'Q5_K_M',
    ];

    final groups = groupCachedModels(models);
    expect(groups, hasLength(2));

    final deepseek = groups.firstWhere(
      (g) => g.id == 'deepseek-ai/DeepSeek-R1-Distill-Qwen-7B',
    );
    expect(deepseek.hasMultiple, isTrue);
    expect(deepseek.artifacts, hasLength(2));
    expect(
      deepseek.artifacts.map((a) => a.formatLabel).toList(),
      ['GGUF', 'MLX'],
    );
    expect(deepseek.loadSeed.format, 'gguf');
    expect(deepseek.loadableRuntimes.toSet(), {'llamacpp', 'mlx'});
    expect(deepseek.seedForRuntime('mlx').format, 'mlx');
    expect(deepseek.seedForRuntime('llamacpp').format, 'gguf');
    expect(deepseek.artifacts.first.summary, contains('GGUF'));
    expect(deepseek.artifacts.first.summary, contains('Q4_K_M'));
  });

  test('CachedModelArtifact infers mlx from HF-style path', () {
    final art = CachedModelArtifact(
      ModelSuggestion()
        ..id = 'org/model'
        ..path = 'org/model'
        ..bestQuant = 'mlx-8bit',
    );
    expect(art.format, 'mlx');
    expect(art.formatLabel, 'MLX');
  });

  test('CachedModelArtifact infers mlx from absolute vault directory', () {
    final art = CachedModelArtifact(
      ModelSuggestion()
        ..id = 'google/gemma-2-2b'
        ..path =
            '/Users/me/Library/Application Support/elp-dev/data/vault/models/mlx-community_Gemma-2-2B-it-4bit'
        ..bestQuant = '4bit',
    );
    expect(art.format, 'mlx');
    expect(art.formatLabel, 'MLX');
  });

  test('CachedModelArtifact prefers GGUF quant from filename', () {
    final art = CachedModelArtifact(
      ModelSuggestion()
        ..id = 'org/model'
        ..format = 'gguf'
        ..bestQuant = 'mlx-8bit'
        ..filename = 'model-Q4_K_M.gguf'
        ..path = '/tmp/vault/model-Q4_K_M.gguf'
        ..diskSizeGb = 4.4,
    );
    expect(art.quant, 'Q4_K_M');
    expect(art.summary, 'GGUF · Q4_K_M · 4.4 GiB');
  });

  test('loadableRuntimes includes vllm for hf safetensors plus llama for gguf', () {
    final group = CachedModelGroup(
      id: 'org/model',
      artifacts: [
        ModelSuggestion()
          ..id = 'org/model'
          ..format = 'gguf'
          ..bestQuant = 'Q4_K_M'
          ..path = '/vault/model.gguf',
        ModelSuggestion()
          ..id = 'org/model'
          ..format = 'hf'
          ..path = '/vault/model-hf',
      ],
    );
    expect(group.loadableRuntimes.toSet(), {'llamacpp', 'vllm'});
    expect(group.seedForRuntime('vllm').format, 'hf');
  });
}
