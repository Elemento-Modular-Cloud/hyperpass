import 'package:elp_gui/auth/feature_access.dart';
import 'package:elp_gui/grpc_client.dart';
import 'package:elp_gui/l10n/app_localizations.dart';
import 'package:elp_gui/llm/runner/llm_accelerator.dart';
import 'package:elp_gui/llm/runner/llm_runner_providers.dart';
import 'package:elp_gui/llm/runner/llm_runner_screen.dart';
import 'package:elp_gui/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpRunner(
    WidgetTester tester, {
    FeatureAccess access = const FeatureAccess(signedIn: true, guest: false),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final snapshot = probeLlmRunner(
      info: DaemonInfoReply(cpus: 10, hostArch: 'arm64'),
      backends: ListLlmBackendsReply(
        backends: [
          LlmBackendInfo(
            id: 'llamacpp',
            name: 'llama.cpp (llama-server)',
            status: 'ready',
            detail: 'b1',
          ),
        ],
      ),
      platform: TargetPlatform.macOS,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          featureAccessProvider.overrideWith((ref) => access),
          llmRunnerSnapshotProvider.overrideWith((ref) => snapshot),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LlmRunnerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows CPU, GPU, and MPU accelerator cards', (tester) async {
    await pumpRunner(tester);

    expect(find.text('Runner'), findsWidgets);
    expect(find.byKey(const Key('llm-accelerator-cpu')), findsOneWidget);
    expect(find.byKey(const Key('llm-accelerator-gpu')), findsOneWidget);
    expect(find.byKey(const Key('llm-accelerator-mpu')), findsOneWidget);
    expect(find.text('CPU'), findsWidgets);
    expect(find.text('GPU'), findsWidgets);
    expect(find.text('MPU'), findsWidgets);
    expect(find.text('Combine as one runner'), findsOneWidget);
    expect(find.text('Requires license'), findsOneWidget);
  });

  testWidgets('combine action shows the license lock', (tester) async {
    await pumpRunner(tester);

    await tester.tap(find.byKey(const Key('llm-runner-combine')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Combining multiple accelerators into one runner requires a license.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping CPU switches the single selected accelerator',
      (tester) async {
    await pumpRunner(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LlmRunnerScreen)),
    );
    expect(container.read(llmRunnerSelectedIdsProvider).toSet(), {'gpu'});

    await tester.tap(find.byKey(const Key('llm-accelerator-cpu')));
    await tester.pumpAndSettle();

    expect(container.read(llmRunnerSelectedIdsProvider).toSet(), {'cpu'});
  });
}
