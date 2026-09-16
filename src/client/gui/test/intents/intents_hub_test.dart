import 'package:elp_gui/auth/feature_access.dart';
import 'package:elp_gui/intents/intents_hub.dart';
import 'package:elp_gui/intents/intents_screen.dart';
import 'package:elp_gui/l10n/app_localizations.dart';
import 'package:elp_gui/providers.dart';
import 'package:elp_gui/services/compose/compose_store.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:elp_gui/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fixture_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MarketplaceLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      composeCurrentIntentPrefsKey: 'lab',
    });
    library = loadSeedLibrary();
  });

  Future<Widget> buildHub({required bool canUseServices}) async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        marketplaceLibraryProvider.overrideWith((ref) => library),
        sharedPreferencesProvider.overrideWithValue(prefs),
        daemonAvailableProvider.overrideWithValue(false),
        featureAccessProvider.overrideWith(
          (ref) => FeatureAccess(
            signedIn: canUseServices,
            guest: !canUseServices,
          ),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IntentsScreen(),
      ),
    );
  }

  testWidgets('intents hub shows list and compose tabs', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await buildHub(canUseServices: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intents-hub-tab-list')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('intents-hub-tab-compose')),
      findsOneWidget,
    );
    expect(find.text('New composition'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('intents-hub-tab-compose')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('compose-zoom-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-fit')), findsOneWidget);
  });

  testWidgets('opening compose from the sidebar key selects the compose tab',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await buildHub(canUseServices: true));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(IntentsScreen)),
    );
    container.read(sidebarKeyProvider.notifier).set('service-compose');
    await tester.pumpAndSettle();

    expect(container.read(sidebarKeyProvider), IntentsScreen.sidebarKey);
    expect(container.read(intentsHubTabProvider), IntentsHubTab.compose);
    expect(find.byKey(const ValueKey('compose-zoom-in')), findsOneWidget);
  });

  testWidgets('guests do not see the compose tab', (tester) async {
    await tester.pumpWidget(await buildHub(canUseServices: false));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('intents-hub-tabs')), findsNothing);
    expect(find.byKey(const ValueKey('compose-zoom-in')), findsNothing);
  });
}
