import 'package:elp_gui/intents/composition_load.dart';
import 'package:elp_gui/services/compose/compose_graph.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sums members for one composition against host totals', () {
    final load = compositionLoadFromMembers(
      members: const [
        (intent: 'lab', cpus: 2, memBytes: 2 * composeGibibyte),
        (intent: 'lab', cpus: 1, memBytes: 1 * composeGibibyte),
        (intent: 'other', cpus: 8, memBytes: 16 * composeGibibyte),
      ],
      intentName: 'lab',
      cpuHost: 8,
      memHost: 16 * composeGibibyte,
    );
    expect(load.cpus, 3);
    expect(load.memBytes, 3 * composeGibibyte);
    expect(load.cpuRatio, 3 / 8);
    expect(load.memRatio, 3 / 16);
    expect(load.hasHost, isTrue);
  });

  test('graph load ignores LLM nodes and uses resolved VM resources', () {
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: const [
        ComposeNode(
          id: 'vm',
          role: 'box',
          serviceId: '24.04',
          kind: ComposeNodeKind.vm,
          image: '24.04',
          numCores: 4,
          memBytes: 4 * composeGibibyte,
          x: 0,
          y: 0,
        ),
        ComposeNode(
          id: 'llm',
          role: 'model',
          serviceId: 'qwen',
          kind: ComposeNodeKind.llm,
          modelId: 'qwen',
          ctxSize: 8192,
          x: 200,
          y: 0,
        ),
      ],
    );
    final load = compositionLoadFromGraph(
      graph: graph,
      library: const MarketplaceLibrary(services: [], commit: 'test'),
      cpuHost: 8,
      memHost: 32 * composeGibibyte,
    );
    expect(load.cpus, 4);
    expect(load.memBytes, 4 * composeGibibyte);
    expect(load.cpuRatio, 0.5);
  });

  test('parses reserved sizes with a B suffix', () {
    expect(parseOccupancyCpus('4'), 4);
    expect(parseOccupancyBytes('1073741824B'), composeGibibyte);
    expect(parseOccupancyBytes('2GiB'), 2 * composeGibibyte);
  });

  test('uses scheduler claims when instance names match', () {
    final claims = [
      (name: 'lab-box', cpus: 4, memBytes: 4 * composeGibibyte),
      (name: 'other', cpus: 8, memBytes: 8 * composeGibibyte),
    ];
    final load = compositionLoadFromReserved(
      reservedCpus: 1,
      reservedMemBytes: composeGibibyte,
      instanceNames: {'lab-box'},
      claims: claims,
      cpuHost: 8,
      memHost: 16 * composeGibibyte,
    );
    expect(load.cpus, 4);
    expect(load.memBytes, 4 * composeGibibyte);
  });

  test('falls back to row occupancy when no claims match', () {
    final load = compositionLoadFromReserved(
      reservedCpus: 3,
      reservedMemBytes: 3 * composeGibibyte,
      instanceNames: {'lab-box'},
      claims: const [],
      cpuHost: 8,
      memHost: 16 * composeGibibyte,
    );
    expect(load.cpus, 3);
    expect(load.memBytes, 3 * composeGibibyte);
  });
}
