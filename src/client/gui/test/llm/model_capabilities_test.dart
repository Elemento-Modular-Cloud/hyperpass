import 'package:elp_gui/llm/catalogue/model_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects multimodal and tools from known families', () {
    final tags = modelCapabilities(
      id: 'Qwen2.5-VL-7B-Instruct',
      name: 'Qwen2.5 VL',
      useCase: 'multimodal',
    );
    expect(tags, contains(ModelCapability.multimodal));
    expect(tags, contains(ModelCapability.tools));
  });

  test('detects coding and reasoning from name/use case', () {
    expect(
      modelCapabilities(id: 'Qwen2.5-Coder-7B', useCase: 'coding'),
      containsAll([ModelCapability.coding]),
    );
    expect(
      modelCapabilities(id: 'DeepSeek-R1-Distill-Qwen-7B', useCase: 'reasoning'),
      contains(ModelCapability.reasoning),
    );
  });

  test('falls back to chat for instruct models', () {
    expect(
      modelCapabilities(id: 'Llama-3.1-8B-Instruct'),
      contains(ModelCapability.chat),
    );
  });

  test('tags vault-style nemotron ids without use_case', () {
    final tags = modelCapabilities(
      id: 'nvidia/NVIDIA-Nemotron-3-Nano-4B-FP8',
      name: 'nvidia/NVIDIA-Nemotron-3-Nano-4B-FP8',
      hfRepo: 'nvidia/NVIDIA-Nemotron-3-Nano-4B-GGUF',
    );
    expect(tags, contains(ModelCapability.chat));
    expect(tags, contains(ModelCapability.tools));
  });
}
