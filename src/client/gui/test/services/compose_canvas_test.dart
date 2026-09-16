import 'package:elp_gui/l10n/app_localizations.dart';
import 'package:elp_gui/providers.dart';
import 'package:elp_gui/services/compose/compose_canvas.dart';
import 'package:elp_gui/services/compose/compose_graph.dart';
import 'package:elp_gui/services/compose/compose_store.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture_library.dart';

const _qdrantSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: qdrant_v1
outputs:
  /endpoints/api:
    type: url
provides:
  qdrant:
    outputs:
      url: /endpoints/api
requires: {}
''';

const _n8nSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: n8n_v3
outputs: {}
provides: {}
requires:
  qdrant:
    optional: true
    inputs:
      url: qdrant_url
''';

const _minioSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: minio_v1
outputs:
  /endpoints/api:
    type: url
  /endpoints/console:
    type: url
provides: {}
requires: {}
''';

const _emptySpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: empty_v1
outputs: {}
provides: {}
requires: {}
''';

MarketplaceService _specService(String id, String spec) {
  return fixtureService(id: id, extraFiles: {'spec.yaml': spec});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MarketplaceLibrary library;

  setUp(() {
    library = fixtureLibrary([
      _specService('qdrant_v1', _qdrantSpec),
      _specService('n8n_v3', _n8nSpec),
      _specService('minio_v1', _minioSpec),
      _specService('empty_v1', _emptySpec),
    ]);
  });

  test('fit matrix centers content in the viewport', () {
    final matrix = composeFitMatrix(
      content: const Rect.fromLTWH(100, 50, 200, 100),
      viewport: const Size(800, 600),
      padding: 0,
      minScale: 0.1,
      maxScale: 10,
    );
    final scale = matrix.getMaxScaleOnAxis();
    expect(scale, 4); // 800/200
    final origin = MatrixUtils.transformPoint(matrix, const Offset(100, 50));
    expect(origin.dx, 0);
    expect(origin.dy, closeTo(100, 0.01)); // (600 - 400) / 2
  });

  test('nodes in a marquee include overlapping cards', () {
    const a = ComposeNode(
      id: 'a',
      role: 'a',
      serviceId: 'a',
      x: 0,
      y: 0,
    );
    const b = ComposeNode(
      id: 'b',
      role: 'b',
      serviceId: 'b',
      x: 400,
      y: 0,
    );
    final graph = ComposeGraph(intentName: 'lab', nodes: const [a, b]);
    expect(
      composeNodesInRect(graph, library, const Rect.fromLTWH(0, 0, 50, 50)),
      {'a'},
    );
    expect(
      composeNodesInRect(graph, library, const Rect.fromLTWH(0, 0, 500, 80)),
      {'a', 'b'},
    );
  });

  test('scene size covers the viewport at minimum zoom', () {
    final scene = composeSceneSize(const Size(800, 500));
    expect(scene.width, greaterThanOrEqualTo(composeCanvasWidth));
    expect(scene.height, greaterThanOrEqualTo(composeCanvasHeight));
    expect(scene.width * composeMinScale, greaterThanOrEqualTo(800));
    expect(scene.height * composeMinScale, greaterThanOrEqualTo(500));
  });

  test('http output rows increase node height', () {
    const minio = ComposeNode(
      id: 'm',
      role: 'minio',
      serviceId: 'minio_v1',
      x: 0,
      y: 0,
    );
    const empty = ComposeNode(
      id: 'e',
      role: 'empty',
      serviceId: 'empty_v1',
      x: 0,
      y: 0,
    );
    expect(
      composeNodeHeight(minio, library),
      greaterThan(composeNodeHeight(empty, library)),
    );
  });

  Future<ProviderContainer> pumpCanvas(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      composeCurrentIntentPrefsKey: 'lab',
    });
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 1400,
              height: 900,
              child: ComposeCanvas(library: library),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(ComposeCanvas)),
    );
  }

  testWidgets('tapping a node selects it without moving', (tester) async {
    final container = await pumpCanvas(tester);
    final notifier = container.read(composeEditorProvider.notifier);
    notifier.addService(library.byId('empty_v1')!, x: 80, y: 80);
    await tester.pumpAndSettle();

    final node = container.read(composeEditorProvider).graph.nodes.single;
    final before = Offset(node.x, node.y);
    await tester.tap(find.byKey(ValueKey('compose-node-${node.id}')));
    await tester.pumpAndSettle();

    final after = container.read(composeEditorProvider).graph.nodes.single;
    expect(after.x, closeTo(before.dx, 0.5));
    expect(after.y, closeTo(before.dy, 0.5));
    expect(container.read(composeEditorProvider).selectedNodeIds, {node.id});
  });

  testWidgets('a click that jitters below slop does not move a node', (
    tester,
  ) async {
    final container = await pumpCanvas(tester);
    final notifier = container.read(composeEditorProvider.notifier);
    notifier.addService(library.byId('empty_v1')!, x: 80, y: 80);
    await tester.pumpAndSettle();

    final node = container.read(composeEditorProvider).graph.nodes.single;
    final before = Offset(node.x, node.y);
    final card = find.byKey(ValueKey('compose-node-${node.id}'));
    final origin = tester.getRect(card).center;
    await tester.dragFrom(origin, const Offset(4, 3));
    await tester.pumpAndSettle();

    final after = container.read(composeEditorProvider).graph.nodes.single;
    expect(after.x, closeTo(before.dx, 0.5));
    expect(after.y, closeTo(before.dy, 0.5));
    expect(container.read(composeEditorProvider).selectedNodeIds, {node.id});
  });

  testWidgets('dragging a node body moves it', (tester) async {
    final container = await pumpCanvas(tester);
    final notifier = container.read(composeEditorProvider.notifier);
    notifier.addService(library.byId('empty_v1')!, x: 80, y: 80);
    await tester.pumpAndSettle();

    final node = container.read(composeEditorProvider).graph.nodes.single;
    final before = Offset(node.x, node.y);
    final card = find.byKey(ValueKey('compose-node-${node.id}'));
    final origin = tester.getRect(card).topCenter + const Offset(0, 12);
    await tester.dragFrom(origin, const Offset(120, 40));
    await tester.pumpAndSettle();

    final moved = container.read(composeEditorProvider).graph.nodes.single;
    expect(moved.x, greaterThan(before.dx + 40));
    expect(moved.y, greaterThan(before.dy + 10));
  });

  testWidgets('node drag does not commit the store until pointer up', (
    tester,
  ) async {
    final container = await pumpCanvas(tester);
    final notifier = container.read(composeEditorProvider.notifier);
    notifier.addService(library.byId('empty_v1')!, x: 80, y: 80);
    await tester.pumpAndSettle();

    final node = container.read(composeEditorProvider).graph.nodes.single;
    final before = Offset(node.x, node.y);
    final card = find.byKey(ValueKey('compose-node-${node.id}'));
    final origin = tester.getRect(card).topCenter + const Offset(0, 12);
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(120, 40));
    await tester.pump();

    final mid = container.read(composeEditorProvider).graph.nodes.single;
    expect(mid.x, closeTo(before.dx, 0.5));
    expect(mid.y, closeTo(before.dy, 0.5));

    await gesture.up();
    await tester.pumpAndSettle();

    final moved = container.read(composeEditorProvider).graph.nodes.single;
    expect(moved.x, greaterThan(before.dx + 40));
    expect(moved.y, greaterThan(before.dy + 10));
  });

  testWidgets('dragging an output pin does not move the node', (tester) async {
    final container = await pumpCanvas(tester);
    final notifier = container.read(composeEditorProvider.notifier);
    notifier.addService(library.byId('qdrant_v1')!, x: 80, y: 80);
    await tester.pumpAndSettle();

    final node = container.read(composeEditorProvider).graph.nodes.single;
    final before = Offset(node.x, node.y);
    await tester.drag(
      find.byKey(ValueKey('compose-pin-out-${node.id}-qdrant')),
      const Offset(140, 20),
    );
    await tester.pumpAndSettle();

    final after = container.read(composeEditorProvider).graph.nodes.single;
    expect(after.x, closeTo(before.dx, 1));
    expect(after.y, closeTo(before.dy, 1));
  });

  testWidgets('clicking output then matching input creates an edge', (
    tester,
  ) async {
    final container = await pumpCanvas(tester);
    final notifier = container.read(composeEditorProvider.notifier);
    notifier.addService(library.byId('qdrant_v1')!, x: 80, y: 80);
    notifier.addService(library.byId('n8n_v3')!, x: 420, y: 80);
    await tester.pumpAndSettle();

    final graph = container.read(composeEditorProvider).graph;
    final from = graph.nodes.firstWhere((n) => n.serviceId == 'qdrant_v1');
    final to = graph.nodes.firstWhere((n) => n.serviceId == 'n8n_v3');

    await tester.tap(
      find.byKey(ValueKey('compose-pin-out-${from.id}-qdrant')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('compose-pin-in-${to.id}-qdrant')));
    await tester.pumpAndSettle();

    final edges = container.read(composeEditorProvider).graph.edges;
    expect(edges, isNotEmpty);
    expect(
      edges.any(
        (edge) =>
            edge.from == from.id &&
            edge.to == to.id &&
            edge.contract == 'qdrant',
      ),
      isTrue,
    );
  });

  testWidgets('http outputs render as display-only pins', (tester) async {
    final container = await pumpCanvas(tester);
    container.read(composeEditorProvider.notifier).addService(
          library.byId('minio_v1')!,
          x: 80,
          y: 80,
        );
    await tester.pumpAndSettle();

    final node = container.read(composeEditorProvider).graph.nodes.single;
    expect(find.text('api'), findsOneWidget);
    expect(find.text('console'), findsOneWidget);
    expect(
      find.byKey(ValueKey('compose-http-${node.id}-/endpoints/api')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('compose-http-${node.id}-/endpoints/console')),
      findsOneWidget,
    );
  });

  testWidgets('mandatory input pins show a required mark', (tester) async {
    library = fixtureLibrary([
      _specService('qdrant_v1', _qdrantSpec),
      _specService(
        'n8n_v3',
        '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: n8n_v3
requires:
  qdrant:
    optional: false
    inputs:
      url: qdrant_url
''',
      ),
    ]);
    final container = await pumpCanvas(tester);
    container.read(composeEditorProvider.notifier).addService(
          library.byId('n8n_v3')!,
          x: 80,
          y: 80,
        );
    await tester.pumpAndSettle();

    expect(find.textContaining(composeRequiredMark), findsWidgets);
  });

  testWidgets('opening a composition fits nodes in view', (tester) async {
    final container = await pumpCanvas(tester);
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    expect(controller.value, Matrix4.identity());

    final notifier = container.read(composeEditorProvider.notifier);
    notifier.addService(library.byId('empty_v1')!, x: 800, y: 600);
    await tester.pumpAndSettle();
    expect(controller.value, Matrix4.identity());

    notifier.openIntent('lab');
    await tester.pumpAndSettle();

    final box = tester.renderObject<RenderBox>(find.byType(InteractiveViewer));
    final node = container.read(composeEditorProvider).graph.nodes.single;
    final expected = composeFitMatrix(
      content: composeNodesBounds([node], library),
      viewport: box.size,
    );
    expect(controller.value.storage, expected.storage);
  });

  testWidgets('node cards show resource footers', (tester) async {
    final container = await pumpCanvas(tester);
    final notifier = container.read(composeEditorProvider.notifier);
    notifier.addService(library.byId('empty_v1')!, x: 80, y: 80);
    notifier.addLlm(modelId: 'qwen', ctxSize: 16384, x: 360, y: 80);
    await tester.pumpAndSettle();

    final nodes = container.read(composeEditorProvider).graph.nodes;
    final service = nodes.firstWhere((n) => n.kind == ComposeNodeKind.service);
    final llm = nodes.firstWhere((n) => n.kind == ComposeNodeKind.llm);
    expect(
      find.byKey(ValueKey('compose-node-footer-${service.id}')),
      findsOneWidget,
    );
    expect(find.text('1 CPU · 1 GiB · 5 GiB'), findsOneWidget);
    expect(
      find.byKey(ValueKey('compose-node-footer-${llm.id}')),
      findsOneWidget,
    );
    expect(find.text('llamacpp · 16384 ctx'), findsOneWidget);
  });
}
