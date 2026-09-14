import 'package:elp_gui/l10n/app_localizations.dart';
import 'package:elp_gui/providers.dart';
import 'package:elp_gui/services/compose/compose_graph.dart';
import 'package:elp_gui/services/compose/compose_screen.dart';
import 'package:elp_gui/services/compose/compose_store.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MarketplaceLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      composeCurrentIntentPrefsKey: 'lab',
    });
    library = loadSeedLibrary();
  });

  Future<Widget> buildScreen() async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        marketplaceLibraryProvider.overrideWith((ref) => library),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ComposeScreen(),
      ),
    );
  }

  testWidgets('palette lists marketplace families', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Compose'), findsWidgets);
    expect(find.text('Services'), findsWidgets);
    expect(find.text('VMs'), findsOneWidget);
    expect(find.text('LLMs'), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-zoom-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-zoom-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-fit')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('compose-palette-qdrant_v1'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('compose-palette-n8n_v3'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a palette service adds a node', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await buildScreen());
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(
        const ValueKey('compose-palette-qdrant_v1'),
        skipOffstage: false,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('compose-palette-qdrant_v1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('qdrant'), findsWidgets);
  });

  testWidgets('incompatible pin drop is rejected', (tester) async {
    await tester.pumpWidget(await buildScreen());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ComposeScreen)),
    );
    final notifier = container.read(composeEditorProvider.notifier);
    notifier.addService(library.byId('qdrant_v1')!);
    notifier.addService(library.byId('minio_v1')!);
    final graph = container.read(composeEditorProvider).graph;
    final from = graph.nodes.firstWhere((n) => n.serviceId == 'qdrant_v1');
    final to = graph.nodes.firstWhere((n) => n.serviceId == 'minio_v1');

    final added = notifier.addEdge(
      ComposeEdge(from: from.id, to: to.id, contract: 'qdrant'),
      library,
    );
    expect(added, isFalse);
    expect(container.read(composeEditorProvider).graph.edges, isEmpty);
  });
}
