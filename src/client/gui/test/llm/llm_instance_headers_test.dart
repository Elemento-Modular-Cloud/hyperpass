import 'package:elp_gui/copyable_text.dart';
import 'package:elp_gui/l10n/app_localizations.dart';
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: LlmModelLink(model)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ModelProviderBadge), findsOneWidget);
    expect(find.text('nvidia/NVIDIA-Nemotron-3-Nano-4B-FP8'), findsOneWidget);
  });

  testWidgets('API id column is a copyable model name box', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: LlmCopyableModelName('gemma-2-2b-63898e47'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CopyableText), findsOneWidget);
    expect(find.text('gemma-2-2b-63898e47'), findsOneWidget);
  });

  test('API model name prefers the OpenAI id', () {
    expect(
      llmApiModelName(
        LoadedModelInfo()
          ..modelId = 'Gemma-2-2B'
          ..openaiId = 'gemma-2-2b-63898e47',
      ),
      'gemma-2-2b-63898e47',
    );
    expect(
      llmApiModelName(LoadedModelInfo()..modelId = 'Gemma-2-2B'),
      'Gemma-2-2B',
    );
  });

  test('running models table includes an ID header', () {
    expect(
      llmInstanceHeaders.map((h) => h.name),
      containsAll(['MODEL', 'ID']),
    );
  });
}
