import 'package:elp_gui/cloud_init/cloud_init_store.dart';
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
    final picker = tester.getRect(find.byType(DropdownButtonFormField<String>));
    final deploy = tester.getRect(find.text('Deploy composition'));
    expect(picker.top, lessThan(deploy.bottom));
    expect(deploy.top, lessThan(picker.bottom));
    expect(deploy.right, greaterThan(tester.view.physicalSize.width - 80));
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

  testWidgets('n8n runner inspector hides generated secrets', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await buildScreen());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ComposeScreen)),
    );
    container
        .read(composeEditorProvider.notifier)
        .addService(library.byId('n8n_runner_v1')!);
    await tester.pumpAndSettle();

    expect(find.text('n8n sandbox'), findsWidgets);
    expect(find.textContaining(composeRequiredMark), findsWidgets);
    expect(find.text('sandbox_api_key'), findsNothing);
    expect(find.text('sandbox_registration_token'), findsNothing);
    expect(find.text('sandbox_runner_api_key'), findsNothing);
  });

  testWidgets('inspector edits cpu ram storage and context', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await buildScreen());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ComposeScreen)),
    );
    final notifier = container.read(composeEditorProvider.notifier);
    notifier.addService(library.byId('qdrant_v1')!);
    await tester.pumpAndSettle();

    var node = container.read(composeEditorProvider).graph.nodes.single;
    await tester.enterText(find.byKey(ValueKey('compose-cpu-${node.id}')), '6');
    await tester.enterText(find.byKey(ValueKey('compose-ram-${node.id}')), '3');
    await tester.enterText(find.byKey(ValueKey('compose-disk-${node.id}')), '12');
    await tester.pumpAndSettle();

    node = container.read(composeEditorProvider).graph.nodes.single;
    expect(node.numCores, 6);
    expect(node.memBytes, 3 * composeGibibyte);
    expect(node.diskBytes, 12 * composeGibibyte);
    expect(find.text('6 CPU · 3 GiB · 12 GiB'), findsWidgets);

    notifier.addLlm(modelId: 'qwen', ctxSize: 8192);
    await tester.pumpAndSettle();
    final llm = container
        .read(composeEditorProvider)
        .graph
        .nodes
        .firstWhere((n) => n.kind == ComposeNodeKind.llm);
    await tester.enterText(find.byKey(ValueKey('compose-ctx-${llm.id}')), '24576');
    await tester.enterText(
      find.byKey(ValueKey('compose-runtime-${llm.id}')),
      'llamacpp',
    );
    await tester.enterText(
      find.byKey(ValueKey('compose-quant-${llm.id}')),
      'Q5_K_M',
    );
    await tester.enterText(
      find.byKey(ValueKey('compose-max-tokens-${llm.id}')),
      '512',
    );
    await tester.pumpAndSettle();
    final updatedLlm = container
        .read(composeEditorProvider)
        .graph
        .nodes
        .firstWhere((n) => n.id == llm.id);
    expect(updatedLlm.ctxSize, 24576);
    expect(updatedLlm.runtime, 'llamacpp');
    expect(updatedLlm.quant, 'Q5_K_M');
    expect(updatedLlm.maxTokens, 512);
  });

  testWidgets('inspector edits vm resources and cloud-init', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          marketplaceLibraryProvider.overrideWith((ref) => library),
          sharedPreferencesProvider.overrideWithValue(prefs),
          cloudInitConfigsProvider.overrideWith(
            (ref) async => [
              CloudInitConfigInfo(
                name: 'lab-init',
                modified: DateTime.utc(2026),
              ),
            ],
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ComposeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ComposeScreen)),
    );
    container.read(composeEditorProvider.notifier).addVm(
          image: '24.04',
          label: 'Ubuntu',
        );
    await tester.pumpAndSettle();

    final node = container.read(composeEditorProvider).graph.nodes.single;
    await tester.enterText(find.byKey(ValueKey('compose-cpu-${node.id}')), '4');
    await tester.enterText(find.byKey(ValueKey('compose-ram-${node.id}')), '2');
    await tester.enterText(find.byKey(ValueKey('compose-disk-${node.id}')), '10');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('compose-cloud-init-${node.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lab-init').last);
    await tester.pumpAndSettle();

    final updated = container.read(composeEditorProvider).graph.nodes.single;
    expect(updated.numCores, 4);
    expect(updated.memBytes, 2 * composeGibibyte);
    expect(updated.diskBytes, 10 * composeGibibyte);
    expect(updated.cloudInitName, 'lab-init');
  });
}
