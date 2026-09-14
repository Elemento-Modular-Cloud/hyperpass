import 'package:elp_gui/services/compose/compose_canvas.dart';
import 'package:elp_gui/services/compose/compose_graph.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MarketplaceLibrary library;

  setUp(() {
    library = MarketplaceLibrary.parse(
      '{"schema":1,"source":{"commit":"test"},"services":[]}',
    );
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
}
