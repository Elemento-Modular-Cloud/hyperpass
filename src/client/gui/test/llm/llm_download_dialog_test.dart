import 'package:elp_gui/l10n/app_localizations.dart';
import 'package:elp_gui/llm/llm_download.dart';
import 'package:elp_gui/llm/llm_download_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required LlmDownloadForm initial,
    List<({String id, String name})> runtimes = const [
      (id: 'llamacpp', name: 'llama.cpp'),
      (id: 'mlx', name: 'MLX'),
    ],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context)!;
            return Scaffold(
              body: TextButton(
                onPressed: () => promptLlmDownloadSettings(
                  context,
                  l10n,
                  availableRuntimes: runtimes,
                  initial: initial,
                ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('defaults to recommended quant and requires a runtime', (tester) async {
    await pumpDialog(
      tester,
      initial: LlmDownloadForm(runtimes: {'llamacpp'}),
    );

    expect(find.text('Download options'), findsOneWidget);
    expect(find.byKey(const Key('llm-download-runtime-llamacpp')), findsOneWidget);
    expect(find.byKey(const Key('llm-download-quant-recommended')), findsOneWidget);
    expect(find.byKey(const Key('llm-download-quant-all')), findsOneWidget);

    final allTile = tester.widget<RadioListTile<LlmDownloadQuantMode>>(
      find.byKey(const Key('llm-download-quant-all')),
    );
    expect(allTile.onChanged, isNotNull);
  });

  testWidgets('disables all-quants when llama.cpp is unchecked', (tester) async {
    await pumpDialog(
      tester,
      initial: LlmDownloadForm(runtimes: {'mlx'}),
      runtimes: const [
        (id: 'llamacpp', name: 'llama.cpp'),
        (id: 'mlx', name: 'MLX'),
      ],
    );

    final allTile = tester.widget<RadioListTile<LlmDownloadQuantMode>>(
      find.byKey(const Key('llm-download-quant-all')),
    );
    expect(allTile.onChanged, isNull);

    await tester.tap(find.byKey(const Key('llm-download-runtime-llamacpp')));
    await tester.pumpAndSettle();

    final enabled = tester.widget<RadioListTile<LlmDownloadQuantMode>>(
      find.byKey(const Key('llm-download-quant-all')),
    );
    expect(enabled.onChanged, isNotNull);
  });

  testWidgets('rejects empty runtime selection', (tester) async {
    await pumpDialog(
      tester,
      initial: LlmDownloadForm(runtimes: {'llamacpp'}),
      runtimes: const [(id: 'llamacpp', name: 'llama.cpp')],
    );

    await tester.tap(find.byKey(const Key('llm-download-runtime-llamacpp')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(find.text('Download options'), findsOneWidget);
    expect(find.text('Select at least one runtime.'), findsOneWidget);
  });
}
