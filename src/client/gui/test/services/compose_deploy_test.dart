import 'package:elp_gui/services/compose/compose_deploy.dart';
import 'package:elp_gui/services/compose/compose_graph.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:elp_gui/services/service_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_library.dart';

const _qdrantSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: qdrant_v1
inputs: {}
outputs:
  /endpoints/api:
    type: url
provides:
  qdrant:
    outputs:
      url: /endpoints/api
      api_key: /credentials/tokens/0
requires: {}
''';

const _n8nSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: n8n_v3
inputs:
  qdrant_url:
    type: url
  qdrant_api_key:
    type: secret
outputs: {}
provides: {}
requires:
  qdrant:
    optional: true
    inputs:
      url: qdrant_url
      api_key: qdrant_api_key
''';

void main() {
  test('deploys producers first and binds contract values', () async {
    final library = fixtureLibrary([
      fixtureService(id: 'qdrant_v1', extraFiles: {'spec.yaml': _qdrantSpec}),
      fixtureService(id: 'n8n_v3', extraFiles: {'spec.yaml': _n8nSpec}),
    ]);
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: const [
        ComposeNode(
          id: 'a',
          role: 'qdrant',
          serviceId: 'qdrant_v1',
          x: 0,
          y: 0,
        ),
        ComposeNode(
          id: 'b',
          role: 'n8n',
          serviceId: 'n8n_v3',
          x: 200,
          y: 0,
        ),
      ],
      edges: const [
        ComposeEdge(from: 'a', to: 'b', contract: 'qdrant'),
      ],
    );

    final created = <String>[];
    final added = <String>[];
    final bound = <String, String>{};
    Map<String, String>? n8nVariables;

    final host = ComposeDeployHost(
      intentExists: (_) => false,
      createIntent: (name) async => created.add(name),
      existingRoles: (_) => {},
      addMember: ({
        required intentName,
        required node,
        required service,
        required variables,
      }) async {
        added.add(node.role);
        if (node.role == 'n8n') n8nVariables = Map.of(variables);
      },
      waitForReady: ({
        required node,
        required instanceName,
        required service,
      }) async {
        return ServiceInfoDocument.parse('''
{
  "api_version": "elemento.service_info/v1",
  "service": "${service!.id}",
  "status": "ready",
  "endpoints": {"api": "https://qdrant.example"},
  "credentials": {"tokens": ["qdrant-secret"]}
}
''');
      },
      bindInstance: (name, id) => bound[name] = id,
    );

    await deployComposeGraph(
      graph: graph,
      library: library,
      host: host,
      onProgress: (_) {},
    );

    expect(created, ['lab']);
    expect(added, ['qdrant', 'n8n']);
    expect(bound, {
      'lab-qdrant': 'qdrant_v1',
      'lab-n8n': 'n8n_v3',
    });
    expect(n8nVariables, {
      'qdrant_url': 'https://qdrant.example',
      'qdrant_api_key': 'qdrant-secret',
    });
  });

  test('deploys vm nodes without marketplace binding', () async {
    final library = fixtureLibrary([]);
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: const [
        ComposeNode(
          id: 'a',
          role: 'web',
          serviceId: 'ubuntu',
          kind: ComposeNodeKind.vm,
          image: 'ubuntu',
          x: 0,
          y: 0,
        ),
      ],
    );
    final added = <String>[];
    final bound = <String, String>{};
    final host = ComposeDeployHost(
      intentExists: (_) => true,
      createIntent: (_) async {},
      existingRoles: (_) => {},
      addMember: ({
        required intentName,
        required node,
        required service,
        required variables,
      }) async {
        added.add('${node.kind.name}:${node.image}');
      },
      waitForReady: ({
        required node,
        required instanceName,
        required service,
      }) async =>
          null,
      bindInstance: (name, id) => bound[name] = id,
    );

    await deployComposeGraph(
      graph: graph,
      library: library,
      host: host,
      onProgress: (_) {},
    );

    expect(added, ['vm:ubuntu']);
    expect(bound, isEmpty);
  });

  test('binds local llm openai output into a service consumer', () async {
    final library = fixtureLibrary([
      fixtureService(id: 'n8n_v3', extraFiles: {'spec.yaml': _n8nOpenAiSpec}),
    ]);
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: const [
        ComposeNode(
          id: 'a',
          role: 'model',
          serviceId: 'qwen',
          kind: ComposeNodeKind.llm,
          modelId: 'qwen',
          x: 0,
          y: 0,
        ),
        ComposeNode(
          id: 'b',
          role: 'n8n',
          serviceId: 'n8n_v3',
          x: 200,
          y: 0,
        ),
      ],
      edges: const [
        ComposeEdge(from: 'a', to: 'b', contract: 'openai_compatible'),
      ],
    );

    Map<String, String>? n8nVariables;
    final host = ComposeDeployHost(
      intentExists: (_) => true,
      createIntent: (_) async {},
      existingRoles: (_) => {},
      addMember: ({
        required intentName,
        required node,
        required service,
        required variables,
      }) async {
        if (node.role == 'n8n') n8nVariables = Map.of(variables);
      },
      waitForReady: ({
        required node,
        required instanceName,
        required service,
      }) async {
        if (node.kind == ComposeNodeKind.llm) {
          return ServiceInfoDocument.parse('''
{
  "api_version": "elemento.service_info/v1",
  "service": "qwen",
  "status": "ready",
  "endpoints": {"api": "http://192.168.67.1:11434/v1"},
  "credentials": {"tokens": ["local"]},
  "model": "qwen"
}
''');
        }
        return ServiceInfoDocument.parse('''
{
  "api_version": "elemento.service_info/v1",
  "service": "n8n_v3",
  "status": "ready",
  "endpoints": {},
  "credentials": {}
}
''');
      },
      bindInstance: (_, __) {},
    );

    await deployComposeGraph(
      graph: graph,
      library: library,
      host: host,
      onProgress: (_) {},
    );

    expect(n8nVariables, {
      'model_url': 'http://192.168.67.1:11434/v1',
      'model_api_key': 'local',
    });
  });

  test('two openai edges bind collect lists on the consumer', () async {
    final library = fixtureLibrary([
      fixtureService(
          id: 'openwebui_v1', extraFiles: {'spec.yaml': _owuCollectSpec}),
    ]);
    final graph = ComposeGraph(
      intentName: 'lab',
      nodes: const [
        ComposeNode(
          id: 'a',
          role: 'model-a',
          serviceId: 'qwen',
          kind: ComposeNodeKind.llm,
          modelId: 'qwen',
          x: 0,
          y: 0,
        ),
        ComposeNode(
          id: 'b',
          role: 'model-b',
          serviceId: 'gemma',
          kind: ComposeNodeKind.llm,
          modelId: 'gemma',
          x: 0,
          y: 80,
        ),
        ComposeNode(
          id: 'c',
          role: 'openwebui',
          serviceId: 'openwebui_v1',
          x: 200,
          y: 0,
        ),
      ],
      edges: const [
        ComposeEdge(from: 'a', to: 'c', contract: 'openai_compatible'),
        ComposeEdge(from: 'b', to: 'c', contract: 'openai_compatible'),
      ],
    );

    Map<String, String>? owuVariables;
    final host = ComposeDeployHost(
      intentExists: (_) => true,
      createIntent: (_) async {},
      existingRoles: (_) => {},
      addMember: ({
        required intentName,
        required node,
        required service,
        required variables,
      }) async {
        if (node.role == 'openwebui') owuVariables = Map.of(variables);
      },
      waitForReady: ({
        required node,
        required instanceName,
        required service,
      }) async {
        if (node.kind == ComposeNodeKind.llm) {
          return ServiceInfoDocument.parse('''
{
  "api_version": "elemento.service_info/v1",
  "service": "${node.modelId}",
  "status": "ready",
  "endpoints": {"api": "http://${node.modelId}.example/v1"},
  "credentials": {"tokens": ["key-${node.modelId}"]},
  "model": "${node.modelId}"
}
''');
        }
        return ServiceInfoDocument.parse('''
{
  "api_version": "elemento.service_info/v1",
  "service": "openwebui_v1",
  "status": "ready",
  "endpoints": {},
  "credentials": {}
}
''');
      },
      bindInstance: (_, __) {},
    );

    await deployComposeGraph(
      graph: graph,
      library: library,
      host: host,
      onProgress: (_) {},
    );

    expect(owuVariables, {
      'openai_base_urls': 'http://qwen.example/v1;http://gemma.example/v1',
      'openai_api_keys': 'key-qwen;key-gemma',
    });
  });
}

const _owuCollectSpec = '''
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
''';

const _n8nOpenAiSpec = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: n8n_v3
inputs:
  model_url:
    type: url
    required: false
  model_api_key:
    type: secret
    required: false
    secret: true
outputs: {}
provides: {}
requires:
  openai_compatible:
    optional: true
    inputs:
      base_url: model_url
      api_key: model_api_key
''';
