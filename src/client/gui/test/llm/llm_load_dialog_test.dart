import 'package:elp_gui/l10n/app_localizations.dart';
import 'package:elp_gui/llm/llm_load.dart';
import 'package:elp_gui/llm/llm_load_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required LlmLoadForm initial,
    List<({String id, String name})> runtimes = const [
      (id: 'llamacpp', name: 'llama.cpp'),
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
                onPressed: () => promptLlmLoadSettings(
                  context,
                  l10n,
                  readyRuntimes: runtimes,
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

  testWidgets('seeds last-used context and shows advanced for llama.cpp', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      initial: LlmLoadForm(ctxSize: 16384, maxTokens: 256),
    );

    expect(find.text('Load settings'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('llm-load-ctx'))).controller?.text,
        '16384');
    expect(find.byKey(const Key('llm-load-advanced')), findsOneWidget);
    expect(find.byKey(const Key('llm-load-gpu')), findsOneWidget);

    final ctx = tester.getTopLeft(find.byKey(const Key('llm-load-ctx')));
    final maxTokens = tester.getTopLeft(find.byKey(const Key('llm-load-max-tokens')));
    expect(maxTokens.dy, closeTo(ctx.dy, 8));
    expect(maxTokens.dx, greaterThan(ctx.dx));
  });

  testWidgets('hides llama advanced controls for mlx', (tester) async {
    await pumpDialog(
      tester,
      initial: LlmLoadForm(runtime: 'mlx', ctxSize: 4096),
      runtimes: const [(id: 'mlx', name: 'MLX')],
    );

    expect(find.byKey(const Key('llm-load-advanced')), findsNothing);
    expect(find.byKey(const Key('llm-load-gpu')), findsNothing);
    expect(find.byKey(const Key('llm-load-ctx')), findsOneWidget);
  });

  testWidgets('rejects a zero context size', (tester) async {
    await pumpDialog(tester, initial: LlmLoadForm());

    await tester.enterText(find.byKey(const Key('llm-load-ctx')), '0');
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();

    expect(find.text('Load settings'), findsOneWidget);
    expect(find.textContaining('Context must be greater than 0'), findsOneWidget);
  });
}
