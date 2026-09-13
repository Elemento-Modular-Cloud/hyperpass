import 'package:elp_gui/intents/intent_add_member.dart';
import 'package:elp_gui/l10n/app_localizations.dart';
import 'package:elp_gui/providers.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fixture_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MarketplaceLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    library = loadSeedLibrary();
  });

  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          marketplaceLibraryProvider.overrideWith((ref) => library),
          sharedPreferencesProvider.overrideWithValue(prefs),
          daemonAvailableProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showAddMemberDialog(context, ref, 'lab'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists marketplace services to add to an intent', (tester) async {
    await openDialog(tester);

    expect(find.text('Services'), findsWidgets);
    expect(find.text('VMs'), findsOneWidget);
    expect(find.text('LLMs'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'qdrant');
    await tester.pumpAndSettle();

    expect(find.text('Qdrant', skipOffstage: false), findsWidgets);
    expect(
      find.byKey(
        const ValueKey('intent-add-service-qdrant_v1'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('VM and LLM tabs are reachable', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('VMs'));
    await tester.pumpAndSettle();
    expect(find.text('No matching VM images.'), findsOneWidget);

    await tester.tap(find.text('LLMs'));
    await tester.pumpAndSettle();
    expect(find.text('No downloaded models yet.'), findsOneWidget);
  });
}
