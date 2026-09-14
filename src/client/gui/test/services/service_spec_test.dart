import 'package:elp_gui/services/service_library.dart';
import 'package:elp_gui/services/service_spec.dart';
import 'package:elp_gui/services/service_spec_bind.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_library.dart';

void main() {
  final seed = loadSeedLibrary();

  test('seed services parse spec.yaml when present', () {
    final qdrant = seed.byId('qdrant_v1')!;
    expect(qdrant.spec, isNotNull);
    expect(qdrant.spec!.provides.keys, contains('qdrant'));
    expect(qdrant.spec!.provides.containsKey('caddy_ca'), isFalse);
    expect(qdrant.spec!.requires.keys, contains('caddy_ca'));
    expect(qdrant.spec!.outputs.containsKey('/endpoints/api'), isTrue);
    expect(
      qdrant.spec!.provides['qdrant']!.outputs['api_key'],
      '/credentials/tokens/0',
    );

    final n8n = seed.byId('n8n_v3')!;
    expect(n8n.spec, isNotNull);
    expect(
      n8n.spec!.requires.keys,
      containsAll(['openai_compatible', 'n8n_sandbox', 'qdrant', 'caddy_ca']),
    );
    expect(n8n.spec!.provides.containsKey('caddy_ca'), isFalse);
    expect(
      n8n.spec!.requires['caddy_ca']!.inputs['acme_directory_url'],
      'acme_directory_url',
    );
    expect(n8n.spec!.requires['qdrant']!.inputs['url'], 'qdrant_url');
    expect(n8n.spec!.groups.map((g) => g.name), contains('qdrant'));

    final lms = seed.byId('llmstudio_v1')!;
    expect(lms.spec, isNotNull);
    expect(lms.spec!.provides.containsKey('openai_compatible'), isTrue);
    expect(lms.spec!.provides.containsKey('caddy_ca'), isFalse);
    expect(lms.spec!.requires.containsKey('caddy_ca'), isTrue);

    final ca = seed.byId('caddy_ca_v1')!;
    expect(ca.spec!.provides['caddy_ca']!.outputs['ca_url'], '/endpoints/ca');
    expect(
      ca.spec!.provides['caddy_ca']!.outputs['acme_directory_url'],
      '/endpoints/acme',
    );
    expect(ca.spec!.requires, isEmpty);
    expect(ca.variables, isEmpty);

    final owu = seed.byId('openwebui_v1')!;
    final owuOpenAi = owu.spec!.requires['openai_compatible']!;
    expect(owuOpenAi.min, 0);
    expect(owuOpenAi.max, isNull);
    expect(owuOpenAi.collect['base_url'], 'openai_base_urls');
    expect(allowsManyIncoming(owuOpenAi), isTrue);

    final litellm = seed.byId('litellm_v1')!;
    expect(litellm.spec!.provides['openai_compatible']!.max, 1);
    expect(litellm.spec!.requires['openai_compatible']!.max, isNull);
    expect(
      litellm.spec!.requires['openai_compatible']!.collect['model'],
      'openai_peer_models',
    );
  });

  test('invalid spec.yaml is ignored so the catalog still loads', () {
    final service = fixtureService(
      id: 'broken_v1',
      extraFiles: {'spec.yaml': 'not: [valid: yaml'},
    );
    expect(service.spec, isNull);
    expect(service.composeSpec.inputs, isEmpty);
  });

  test('lookupPointer walks objects and arrays', () {
    final json = <String, Object?>{
      'endpoints': {'api': 'https://qdrant.example/v1'},
      'credentials': {
        'tokens': ['secret-token-1', 'other'],
      },
    };
    expect(
      lookupPointer(json, '/endpoints/api'),
      'https://qdrant.example/v1',
    );
    expect(lookupPointer(json, '/credentials/tokens/0'), 'secret-token-1');
    expect(lookupPointer(json, '/credentials/missing'), isNull);
    expect(stringifyPointerValue(['a', 'b']), '["a","b"]');
  });

  test('bindContract maps qdrant outputs onto n8n inputs', () {
    final qdrant = seed.byId('qdrant_v1')!.composeSpec;
    final n8n = seed.byId('n8n_v3')!.composeSpec;
    final info = <String, Object?>{
      'api_version': 'elemento.service_info/v1',
      'service': 'qdrant_v1',
      'status': 'ready',
      'endpoints': {
        'api': 'https://10.0.0.5.nip.io',
        'ui': 'https://10.0.0.5.nip.io',
        'ca': 'http://10.0.0.5/ca.crt',
      },
      'credentials': {
        'tokens': ['qdrant-secret-token'],
      },
    };

    final bound = bindContract(
      producer: qdrant,
      serviceInfo: info,
      consumer: n8n,
      contractId: 'qdrant',
    );
    expect(bound, {
      'qdrant_url': 'https://10.0.0.5.nip.io',
      'qdrant_api_key': 'qdrant-secret-token',
    });
  });

  test('bindContract skips optional fields the producer omits', () {
    final producer = ServiceSpec.openaiCompatibleProvider('qwen');
    final n8n = seed.byId('n8n_v3')!.composeSpec;
    final bound = bindContract(
      producer: producer,
      serviceInfo: {
        'endpoints': {'api': 'http://192.168.67.1:11434/v1'},
        'credentials': {
          'tokens': ['local'],
        },
        'model': 'qwen',
      },
      consumer: n8n,
      contractId: 'openai_compatible',
    );
    expect(bound['model_url'], 'http://192.168.67.1:11434/v1');
    expect(bound['model_api_key'], 'local');
    expect(bound['model_name'], 'qwen');
    expect(bound.containsKey('ca_url'), isFalse);
  });

  Map<String, Object?> lmsInfo(String host, String token, {String? ca}) {
    return {
      'endpoints': {
        'api': 'https://$host/v1',
        'ca': ca ?? 'http://${host.split('.').first}/ca.crt',
      },
      'credentials': {
        'tokens': [token],
      },
    };
  }

  test('bindContracts uses scalars for one producer and collect for many', () {
    final producer = seed.byId('llmstudio_v1')!.composeSpec;
    final owu = seed.byId('openwebui_v1')!.composeSpec;
    final litellm = seed.byId('litellm_v1')!.composeSpec;

    expect(
      bindContracts(
        producers: const [],
        consumer: owu,
        contractId: 'openai_compatible',
      ),
      isEmpty,
    );

    final oneInfo = lmsInfo(
      '10.0.0.5.nip.io',
      'secret-token-1',
      ca: 'http://10.0.0.5/ca.crt',
    );
    final one = bindContracts(
      producers: [
        ContractProducer(spec: producer, serviceInfo: oneInfo),
      ],
      consumer: owu,
      contractId: 'openai_compatible',
    );
    expect(
      one,
      bindContract(
        producer: producer,
        serviceInfo: oneInfo,
        consumer: owu,
        contractId: 'openai_compatible',
      ),
    );
    expect(one, {
      'openai_base_url': 'https://10.0.0.5.nip.io/v1',
      'openai_api_key': 'secret-token-1',
      'ca_url': 'http://10.0.0.5/ca.crt',
    });

    final twoOwu = bindContracts(
      producers: [
        ContractProducer(
          spec: producer,
          serviceInfo: lmsInfo(
            '10.0.0.5.nip.io',
            'token-a',
            ca: 'http://10.0.0.5/ca.crt',
          ),
        ),
        ContractProducer(
          spec: producer,
          serviceInfo: lmsInfo(
            '10.0.0.6.nip.io',
            'token-b',
            ca: 'http://10.0.0.6/ca.crt',
          ),
        ),
      ],
      consumer: owu,
      contractId: 'openai_compatible',
    );
    expect(twoOwu, {
      'openai_base_urls':
          'https://10.0.0.5.nip.io/v1;https://10.0.0.6.nip.io/v1',
      'openai_api_keys': 'token-a;token-b',
      'ca_urls': 'http://10.0.0.5/ca.crt;http://10.0.0.6/ca.crt',
    });
    expect(twoOwu.containsKey('openai_base_url'), isFalse);

    final twoLite = bindContracts(
      producers: [
        ContractProducer(
          spec: producer,
          serviceInfo: lmsInfo(
            '10.0.0.5.nip.io',
            'token-a',
            ca: 'http://10.0.0.5/ca.crt',
          ),
        ),
        ContractProducer(
          spec: producer,
          serviceInfo: lmsInfo(
            '10.0.0.6.nip.io',
            'token-b',
            ca: 'http://10.0.0.5/ca.crt',
          ),
        ),
      ],
      consumer: litellm,
      contractId: 'openai_compatible',
    );
    expect(twoLite, {
      'openai_base_urls':
          'https://10.0.0.5.nip.io/v1;https://10.0.0.6.nip.io/v1',
      'openai_api_keys_local': 'token-a;token-b',
      'openai_peer_models': 'local;local-2',
      'ca_urls': 'http://10.0.0.5/ca.crt',
    });

    expect(
      () => bindContracts(
        producers: [
          ContractProducer(
            spec: producer,
            serviceInfo: lmsInfo('10.0.0.5.nip.io', 'token-a'),
          ),
          ContractProducer(
            spec: producer,
            serviceInfo: lmsInfo('10.0.0.6.nip.io', 'token-b'),
          ),
        ],
        consumer: seed.byId('n8n_v3')!.composeSpec,
        contractId: 'openai_compatible',
      ),
      throwsStateError,
    );
  });

  test('bindContracts maps issuer caddy_ca onto n8n including ACME', () {
    final issuer = seed.byId('caddy_ca_v1')!.composeSpec;
    final n8n = seed.byId('n8n_v3')!.composeSpec;
    final bound = bindContracts(
      producers: [
        ContractProducer(
          spec: issuer,
          serviceInfo: const {
            'endpoints': {
              'ca': 'http://10.0.0.9/ca.crt',
              'acme': 'http://10.0.0.9/acme/elemento/directory',
            },
          },
        ),
      ],
      consumer: n8n,
      contractId: 'caddy_ca',
    );
    expect(bound, {
      'ca_url': 'http://10.0.0.9/ca.crt',
      'acme_directory_url': 'http://10.0.0.9/acme/elemento/directory',
    });
  });

  test('bindContract rejects unknown contracts', () {
    final qdrant = seed.byId('qdrant_v1')!.composeSpec;
    final n8n = seed.byId('n8n_v3')!.composeSpec;
    expect(
      () => bindContract(
        producer: qdrant,
        serviceInfo: const {},
        consumer: n8n,
        contractId: 'postgres',
      ),
      throwsStateError,
    );
  });

  test('empty spec falls back to scanned placeholders', () {
    final service = fixtureService(
      id: 'plain_v1',
      extraFiles: {
        'files/app.env': 'TOKEN={{token}}\n',
        'spec.yaml':
            'api_version: elemento.spec/v1\nkind: ServiceSpec\nmetadata:\n  name: plain_v1\ninputs: {}\noutputs: {}\nprovides: {}\nrequires: {}\n',
      },
      fileSources: ['files/app.env'],
    );
    expect(service.spec, isNotNull);
    expect(service.spec!.hasContracts, isFalse);
    expect(service.composeSpec.inputs.keys, contains('token'));
  });

  test('ServiceSpec.parse reads groups and optional requires', () {
    const yaml = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: demo
inputs:
  model_url:
    type: url
    required: false
  model_api_key:
    type: secret
    required: false
    secret: true
groups:
  instance_ai_model:
    when: model_url
    require: [model_api_key]
outputs: {}
provides: {}
requires:
  openai_compatible:
    optional: true
    inputs:
      base_url: model_url
      api_key: model_api_key
''';
    final spec = ServiceSpec.parse(yaml);
    expect(spec.groups.single.when, 'model_url');
    expect(spec.groups.single.require, ['model_api_key']);
    expect(spec.requires['openai_compatible']!.optional, isTrue);
    expect(spec.requires['openai_compatible']!.max, 1);
    expect(spec.requires['openai_compatible']!.collect, isEmpty);
    expect(spec.inputs['model_api_key']!.secret, isTrue);
  });

  test('parse reads max null, omitted max, and collect', () {
    const unbounded = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: fan_in
inputs:
  openai_base_url:
    type: url
    required: false
  openai_base_urls:
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
    collect:
      base_url: openai_base_urls
''';
    final fanIn = ServiceSpec.parse(unbounded);
    expect(fanIn.requires['openai_compatible']!.min, 0);
    expect(fanIn.requires['openai_compatible']!.max, isNull);
    expect(
      fanIn.requires['openai_compatible']!.collect,
      {'base_url': 'openai_base_urls'},
    );
    expect(
      incomingLimit(fanIn.requires['openai_compatible']!),
      isNull,
    );

    const collectImpliesUnbounded = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: collect_only
inputs:
  urls:
    type: semicolon_list
    required: false
outputs: {}
provides: {}
requires:
  openai_compatible:
    optional: true
    inputs:
      base_url: url
    collect:
      base_url: urls
''';
    final implied = ServiceSpec.parse(collectImpliesUnbounded);
    expect(implied.requires['openai_compatible']!.max, isNull);

    const omittedMax = '''
api_version: elemento.spec/v1
kind: ServiceSpec
metadata:
  name: one
inputs: {}
outputs: {}
provides:
  openai_compatible:
    outputs:
      base_url: /endpoints/api
requires: {}
''';
    final one = ServiceSpec.parse(omittedMax);
    expect(one.provides['openai_compatible']!.min, 1);
    expect(one.provides['openai_compatible']!.max, 1);
  });
}
