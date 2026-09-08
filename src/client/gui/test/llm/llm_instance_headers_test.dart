import 'package:elp_gui/llm/catalogue/model_branding.dart';
import 'package:elp_gui/llm/instances/llm_instance_headers.dart';
import 'package:elp_gui/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves a provider mark from a running model id', () {
    final branding = brandingForLoaded(
      LoadedModelInfo()
        ..modelId = 'nvidia/NVIDIA-Nemotron-3-Nano-4B-FP8'
        ..path = '/tmp/models/NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf',
    );

    expect(branding.displayName, 'NVIDIA');
    expect(branding.logoAsset, 'assets/llm/nvidia.svg');
  });

  testWidgets('running model cell shows the provider icon next to the name', (
    tester,
  ) async {
    final model = LoadedModelInfo()
      ..modelId = 'nvidia/NVIDIA-Nemotron-3-Nano-4B-FP8'
      ..instanceId = 'inst-1';

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: LlmModelLink(model)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ModelProviderBadge), findsOneWidget);
    expect(find.text('nvidia/NVIDIA-Nemotron-3-Nano-4B-FP8'), findsOneWidget);
  });
}
