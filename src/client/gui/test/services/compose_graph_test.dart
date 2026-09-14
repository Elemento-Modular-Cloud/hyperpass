import 'package:elp_gui/services/compose/compose_graph.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:elp_gui/services/service_spec.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_library.dart';

MarketplaceService _specService({
  required String id,
  required String spec,
}) {
  return fixtureService(
    id: id,
    extraFiles: {'spec.yaml': spec},
  );
}

const _qdrantSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: qdrant_v1
inputs:
  ca_url:
    type: ca_url
    required: false
  acme_directory_url:
    type: url
    required: false
outputs:
  /endpoints/api:
    type: url
provides:
  qdrant:
    outputs:
      url: /endpoints/api
      api_key: /credentials/tokens/0
requires:
  caddy_ca:
    optional: true
    inputs:
      ca_url: ca_url
      acme_directory_url: acme_directory_url
''';

const _n8nSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: n8n_v3
inputs:
  model_url:
    type: url
  model_api_key:
    type: secret
  qdrant_url:
    type: url
  qdrant_api_key:
    type: secret
  ca_url:
    type: ca_url
    required: false
  acme_directory_url:
    type: url
    required: false
groups:
  qdrant:
    when: qdrant_url
    require: [qdrant_api_key]
  instance_ai_model:
    when: model_url
    require: [model_api_key]
outputs: {}
provides: {}
requires:
  qdrant:
    optional: true
    inputs:
      url: qdrant_url
      api_key: qdrant_api_key
  openai_compatible:
    optional: true
    inputs:
      base_url: model_url
      api_key: model_api_key
      ca_url: ca_url
  caddy_ca:
    optional: true
    inputs:
      ca_url: ca_url
      acme_directory_url: acme_directory_url
''';

const _lmsSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: llmstudio_v1
inputs:
  ca_url:
    type: ca_url
    required: false
  acme_directory_url:
    type: url
    required: false
outputs: {}
provides:
  openai_compatible:
    outputs:
      base_url: /endpoints/api
      api_key: /credentials/tokens/0
      ca_url: /endpoints/ca
requires:
  caddy_ca:
    optional: true
    inputs:
      ca_url: ca_url
      acme_directory_url: acme_directory_url
''';

const _issuerSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: caddy_ca_v1
inputs: {}
outputs:
  /endpoints/ca:
    type: ca_url
  /endpoints/acme:
    type: url
provides:
  caddy_ca:
    outputs:
      ca_url: /endpoints/ca
      acme_directory_url: /endpoints/acme
requires: {}
''';

const _openWebUiSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: openwebui_v1
inputs:
  openai_base_url:
    type: url
    required: false
  openai_api_key:
    type: secret
    required: false
  openai_base_urls:
    type: semicolon_list
    required: false
  openai_api_keys:
    type: semicolon_list
    required: false
outputs: {}
provides: {}
requires:
  openai_compatible:
    optional: true
    min: 0
    max: null
    inputs:
      base_url: openai_base_url
      api_key: openai_api_key
    collect:
      base_url: openai_base_urls
      api_key: openai_api_keys
  caddy_ca:
    optional: true
    inputs:
      ca_url: ca_url
''';

void main() {
  late MarketplaceLibrary library;
  late ComposeNode qdrant;
  late ComposeNode n8n;
  late ComposeNode lms;
  late ComposeNode owu;
  late ComposeNode llmA;
  late ComposeNode llmB;

  setUp(() {
    library = fixtureLibrary([
      _specService(id: 'qdrant_v1', spec: _qdrantSpec),
      _specService(id: 'n8n_v3', spec: _n8nSpec),
      _specService(id: 'llmstudio_v1', spec: _lmsSpec),
      _specService(id: 'openwebui_v1', spec: _openWebUiSpec),
      _specService(id: 'caddy_ca_v1', spec: _issuerSpec),
    ]);
    qdrant = const ComposeNode(
      id: 'a',
      role: 'qdrant',
      serviceId: 'qdrant_v1',
      x: 0,
      y: 0,
    );
    n8n = const ComposeNode(
      id: 'b',
      role: 'n8n',
      serviceId: 'n8n_v3',
      x: 200,
      y: 0,
    );
    lms = const ComposeNode(
      id: 'c',
      role: 'llmstudio',
      serviceId: 'llmstudio_v1',
      x: 0,
      y: 200,
    );
    owu = const ComposeNode(
      id: 'owu',
      role: 'openwebui',
      serviceId: 'openwebui_v1',
      x: 200,
      y: 200,
    );
    llmA = const ComposeNode(
      id: 'llm-a',
      role: 'model-a',
      serviceId: 'qwen',
      kind: ComposeNodeKind.llm,
      modelId: 'qwen',
      x: 0,
      y: 400,
    );
    llmB = const ComposeNode(
      id: 'llm-b',
      role: 'model-b',
      serviceId: 'gemma',
      kind: ComposeNodeKind.llm,
      modelId: 'gemma',
      x: 0,
      y: 500,
    );
  });

  test('legal qdrant edge is valid and topo-sorts producer first', () {
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: [n8n, qdrant],
      edges: const [
        ComposeEdge(from: 'a', to: 'b', contract: 'qdrant'),
      ],
    );
    expect(validateComposeGraph(graph, library), isEmpty);
    expect(topoSort(graph)!.map((n) => n.id), ['a', 'b']);
  });

  test('rejects unknown contracts and duplicate incoming pins', () {
    final unknown = ComposeGraph(
      intentName: 'lab',
      nodes: [qdrant, n8n],
      edges: const [
        ComposeEdge(from: 'a', to: 'b', contract: 'postgres'),
      ],
    );
    expect(
      validateComposeGraph(unknown, library).map((i) => i.code),
      containsAll(['missing_provide', 'missing_require']),
    );

    final dup = ComposeGraph(
      intentName: 'lab',
      nodes: [qdrant, n8n],
      edges: const [
        ComposeEdge(from: 'a', to: 'b', contract: 'qdrant'),
        ComposeEdge(from: 'a', to: 'b', contract: 'qdrant'),
      ],
    );
    expect(
      validateComposeGraph(dup, library)
          .any((i) => i.code == 'duplicate_incoming'),
      isTrue,
    );
  });

  test('rejects cycles and duplicate roles', () {
    final cyclic = ComposeGraph(
      intentName: 'lab',
      nodes: [qdrant, n8n],
      edges: const [
        ComposeEdge(from: 'a', to: 'b', contract: 'qdrant'),
        ComposeEdge(from: 'b', to: 'a', contract: 'caddy_ca'),
      ],
    );
    expect(
      validateComposeGraph(cyclic, library).any((i) => i.code == 'cycle'),
      isTrue,
    );

    final dupRole = ComposeGraph(
      intentName: 'lab',
      nodes: [
        qdrant,
        n8n.copyWith(role: 'qdrant'),
      ],
    );
    expect(
      validateComposeGraph(dupRole, library)
          .any((i) => i.code == 'role_duplicate'),
      isTrue,
    );
  });

  test('groups require companion fields when a trigger is set', () {
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: [
        n8n.copyWith(manualParams: const {'model_url': 'https://llm/v1'}),
      ],
    );
    expect(
      validateComposeGraph(graph, library).any((i) => i.code == 'group'),
      isTrue,
    );

    final complete = graph.copyWith(
      nodes: [
        n8n.copyWith(manualParams: const {
          'model_url': 'https://llm/v1',
          'model_api_key': 'sk-test',
        }),
      ],
    );
    expect(validateComposeGraph(complete, library), isEmpty);
  });

  test('canConnect and companion caddy_ca edge', () {
    const issuer = ComposeNode(
      id: 'ca',
      role: 'caddy-ca',
      serviceId: 'caddy_ca_v1',
      x: 0,
      y: 400,
    );
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: [issuer, lms, n8n],
    );
    expect(
      canConnect(
        graph: graph,
        library: library,
        fromId: 'c',
        toId: 'b',
        contract: 'openai_compatible',
      ),
      isTrue,
    );
    expect(
      companionCaddyCaEdge(
        graph: graph.copyWith(
          edges: const [
            ComposeEdge(from: 'c', to: 'b', contract: 'openai_compatible'),
          ],
        ),
        library: library,
        edge: const ComposeEdge(
          from: 'c',
          to: 'b',
          contract: 'openai_compatible',
        ),
      )?.from,
      'ca',
    );
    expect(
      companionCaddyCaEdge(
        graph: ComposeGraph(intentName: 'lab', nodes: [lms, n8n]),
        library: library,
        edge: const ComposeEdge(
          from: 'c',
          to: 'b',
          contract: 'openai_compatible',
        ),
      ),
      isNull,
    );
  });

  test('openai and caddy_ca outputs can fan out to many consumers', () {
    const issuer = ComposeNode(
      id: 'ca',
      role: 'caddy-ca',
      serviceId: 'caddy_ca_v1',
      x: 0,
      y: 400,
    );
    final n8n2 = n8n.copyWith(id: 'd', role: 'n8n-b', x: 400, y: 0);
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: [issuer, lms, n8n, n8n2],
      edges: const [
        ComposeEdge(from: 'c', to: 'b', contract: 'openai_compatible'),
        ComposeEdge(from: 'ca', to: 'b', contract: 'caddy_ca'),
      ],
    );
    expect(
      canConnect(
        graph: graph,
        library: library,
        fromId: 'c',
        toId: 'd',
        contract: openaiCompatibleContract,
      ),
      isTrue,
    );
    expect(
      canConnect(
        graph: graph,
        library: library,
        fromId: 'ca',
        toId: 'd',
        contract: caddyCaContract,
      ),
      isTrue,
    );
    expect(
      isCaddyCaIssuer(specForNode(issuer, library)),
      isTrue,
    );
    expect(
      isCaddyCaIssuer(specForNode(lms, library)),
      isFalse,
    );
  });

  test('suggestComposeRole uniquifies within a graph', () {
    expect(suggestComposeRole('n8n_v3', const []), 'n8n');
    expect(suggestComposeRole('n8n_v3', const ['n8n']), 'n8n-2');
    expect(intentMemberInstanceName('lab', 'qdrant'), 'lab-qdrant');
  });

  test('vm and llm nodes do not need marketplace specs', () {
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: const [
        ComposeNode(
          id: 'vm',
          role: 'web',
          serviceId: 'ubuntu',
          kind: ComposeNodeKind.vm,
          image: 'ubuntu',
          x: 0,
          y: 0,
        ),
        ComposeNode(
          id: 'llm',
          role: 'model',
          serviceId: 'qwen',
          kind: ComposeNodeKind.llm,
          modelId: 'qwen',
          x: 200,
          y: 0,
        ),
      ],
    );
    expect(validateComposeGraph(graph, library), isEmpty);
    final llmSpec = specForNode(graph.nodeById('llm')!, library);
    expect(llmSpec.provides.keys, ['openai_compatible']);
    expect(llmSpec.requires, isEmpty);
    expect(
      canConnect(
        graph: graph,
        library: library,
        fromId: 'llm',
        toId: 'n8n-missing',
        contract: 'openai_compatible',
      ),
      isFalse,
    );
  });

  test('local llm openai pin can wire into n8n', () {
    final llm = const ComposeNode(
      id: 'llm',
      role: 'model',
      serviceId: 'qwen',
      kind: ComposeNodeKind.llm,
      modelId: 'qwen',
      x: 0,
      y: 0,
    );
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: [llm, n8n],
    );
    expect(
      canConnect(
        graph: graph,
        library: library,
        fromId: 'llm',
        toId: 'b',
        contract: openaiCompatibleContract,
      ),
      isTrue,
    );
    expect(composeOutputFansOut(openaiCompatibleContract), isTrue);
    expect(composeOutputFansOut(caddyCaContract), isTrue);
    expect(composePinLabel(openaiCompatibleContract), 'OpenAI');
  });

  test('two LLMs can fan in to Open WebUI OpenAI but not n8n', () {
    final owuGraph = ComposeGraph(
      intentName: 'lab',
      nodes: [llmA, llmB, owu],
      edges: const [
        ComposeEdge(
            from: 'llm-a', to: 'owu', contract: openaiCompatibleContract),
      ],
    );
    expect(
      canConnect(
        graph: owuGraph,
        library: library,
        fromId: 'llm-b',
        toId: 'owu',
        contract: openaiCompatibleContract,
      ),
      isTrue,
    );
    expect(
      validateComposeGraph(
        owuGraph.copyWith(
          edges: [
            ...owuGraph.edges,
            const ComposeEdge(
              from: 'llm-b',
              to: 'owu',
              contract: openaiCompatibleContract,
            ),
          ],
        ),
        library,
      ),
      isEmpty,
    );
    expect(
        composeInputFansIn(specForNode(owu, library), openaiCompatibleContract),
        isTrue);

    final n8nGraph = ComposeGraph(
      intentName: 'lab',
      nodes: [llmA, llmB, n8n],
      edges: const [
        ComposeEdge(from: 'llm-a', to: 'b', contract: openaiCompatibleContract),
      ],
    );
    expect(
      canConnect(
        graph: n8nGraph,
        library: library,
        fromId: 'llm-b',
        toId: 'b',
        contract: openaiCompatibleContract,
      ),
      isFalse,
    );
    expect(
      validateComposeGraph(
        n8nGraph.copyWith(
          edges: [
            ...n8nGraph.edges,
            const ComposeEdge(
              from: 'llm-b',
              to: 'b',
              contract: openaiCompatibleContract,
            ),
          ],
        ),
        library,
      ).any((i) => i.code == 'duplicate_incoming'),
      isTrue,
    );

    final withOpenAi = owuGraph.copyWith(
      nodes: [
        const ComposeNode(
          id: 'ca',
          role: 'caddy-ca',
          serviceId: 'caddy_ca_v1',
          x: 0,
          y: 600,
        ),
        ...owuGraph.nodes,
      ],
      edges: const [
        ComposeEdge(
            from: 'llm-a', to: 'owu', contract: openaiCompatibleContract),
        ComposeEdge(from: 'ca', to: 'owu', contract: caddyCaContract),
        ComposeEdge(
            from: 'llm-b', to: 'owu', contract: openaiCompatibleContract),
      ],
    );
    expect(
      companionCaddyCaEdge(
        graph: withOpenAi,
        library: library,
        edge: const ComposeEdge(
          from: 'llm-b',
          to: 'owu',
          contract: openaiCompatibleContract,
        ),
      ),
      isNull,
    );
  });

  test('hints when a CA issuer is on the canvas but not wired', () {
    const issuer = ComposeNode(
      id: 'ca',
      role: 'caddy-ca',
      serviceId: 'caddy_ca_v1',
      x: 0,
      y: 400,
    );
    final unwired = ComposeGraph(
      intentName: 'lab',
      nodes: [issuer, n8n],
    );
    expect(
      validateComposeGraph(unwired, library).any((i) => i.code == 'ca_unwired'),
      isTrue,
    );
    final wired = unwired.copyWith(
      edges: const [
        ComposeEdge(from: 'ca', to: 'b', contract: 'caddy_ca'),
      ],
    );
    expect(validateComposeGraph(wired, library), isEmpty);
  });
}
