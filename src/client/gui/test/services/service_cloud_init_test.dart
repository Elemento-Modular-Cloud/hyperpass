import 'dart:io';

import 'package:elp_gui/services/gateway_ca.dart';
import 'package:elp_gui/services/service_cloud_init.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'fixture_library.dart';

/// Set this to a directory to dump every rendered service:
///   MARKETPLACE_RENDER_OUT=/tmp/dart-render flutter test test/services
const _outputDirVariable = 'MARKETPLACE_RENDER_OUT';

void main() {
  final seed = loadSeedLibrary();

  test('shipped seed is a last-resort catalog, not a vendor pin', () {
    expect(File(marketplaceSeedAsset).existsSync(), isTrue);
    expect(File('assets/marketplace_services.json').existsSync(), isFalse);
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('\n    - assets/\n'),
    );
    expect(seed.commit, isNot(anyOf('', 'unknown', 'embedded-seed')));
    expect(seed.services, hasLength(16));
    expect(seed.byId('qdrant_v1'), isNotNull);
    expect(seed.byId('minio_v1'), isNotNull);
    expect(seed.byId('n8n_v3'), isNotNull);
    expect(seed.byId('postgres_v2'), isNotNull);
    expect(seed.byId('mariadb_v2'), isNotNull);
  });

  test('seed services expose catalog SVG icons without deploying them', () {
    for (final service in seed.services) {
      expect(service.icon?.svg, 'icon.svg', reason: service.id);
      expect(service.icon?.fontAwesome, isNotEmpty, reason: service.id);
      expect(service.iconSvg, contains('<svg'), reason: service.id);
      expect(
        service.files.map((file) => file.source),
        isNot(contains('icon.svg')),
        reason: service.id,
      );
    }
  });

  test('keeps only the newest release of each service', () {
    final library = fixtureLibrary([
      fixtureService(
          id: 'n8n', displayName: 'n8n Workflow Automation', version: '1.0.0'),
      fixtureService(
          id: 'n8n_v2',
          displayName: 'n8n Workflow Automation',
          version: '2.0.0'),
      fixtureService(
          id: 'n8n_v3',
          displayName: 'n8n Workflow Automation',
          version: '3.4.0'),
      fixtureService(
          id: 'n8n_runner_v1', displayName: 'n8n Runner', version: '1.0.0'),
      fixtureService(
          id: 'postgres_v1', displayName: 'PostgreSQL', version: '1.0.0'),
      fixtureService(
          id: 'postgres_v2', displayName: 'PostgreSQL (apt)', version: '2.0.0'),
    ]);

    expect(library.byId('n8n_v3'), isNotNull);
    expect(library.byId('n8n_v2'), isNull);
    expect(library.byId('n8n'), isNull);
    expect(library.byId('n8n_runner_v1'), isNotNull);
    expect(serviceFamily('n8n_runner_v1'), 'n8n_runner');

    expect(library.byId('postgres_v2'), isNotNull);
    expect(library.byId('postgres_v1'), isNull);
    expect(library.lookup('postgres_v1')?.id, 'postgres_v2');

    final displayNames = library.services.map((s) => s.displayName).toList();
    expect(displayNames, displayNames.toSet().toList());
  });

  test('discovers parameters with their setting name and docs', () {
    final qdrant = seed.byId('qdrant_v1')!;
    expect(qdrant.variables.map((v) => v.name), ['api_key']);

    final apiKey = qdrant.variables.single;
    expect(apiKey.key, 'QDRANT__SERVICE__API_KEY');
    expect(apiKey.label, 'QDRANT__SERVICE__API_KEY');
    expect(apiKey.sources, ['files/qdrant.env']);
    expect(
      apiKey.documentation,
      'API key for REST / dashboard. '
      'Generated on first boot when left as a placeholder.',
    );

    final grouped = fixtureService(
      id: 'router_v1',
      extraFiles: {
        'files/router.env': '# Master token\n'
            'LITELLM_MASTER_KEY={{token}}\n'
            'LITELLM_IMAGE={{litellm_image}}\n'
            'OPENAI_API_KEY={{openai_api_key}}\n'
            'OPENAI_MODEL={{openai_model}}\n',
      },
    );
    expect(grouped.variables, hasLength(4));
    expect(grouped.variables.first.name, 'token');
    expect(grouped.variables.first.key, 'LITELLM_MASTER_KEY');
    expect(
      grouped.variables.map((v) => v.name),
      ['token', 'litellm_image', 'openai_api_key', 'openai_model'],
    );
  });

  group('renders every seed service', () {
    final outputDir = Platform.environment[_outputDirVariable];

    for (final service in seed.services) {
      test(service.id, () {
        final rendered = renderServiceCloudInit(service);

        if (outputDir != null) {
          final file = File('$outputDir/${service.id}.yaml');
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(rendered);
        }

        expect(rendered, startsWith('#cloud-config\n'));

        final config = loadYaml(rendered) as YamlMap;

        expect(config['resize_rootfs'], isTrue);
        expect((config['growpart'] as YamlMap)['mode'], 'auto');
        expect(config['packages'], contains('cloud-guest-utils'));
        expect(
          (config['runcmd'] as YamlList).first.toString(),
          contains('growpart'),
        );

        final writeFiles = config['write_files'] as YamlList;
        expect(writeFiles, hasLength(service.files.length));
        for (final spec in service.files) {
          final entry = writeFiles.firstWhere(
            (candidate) => (candidate as YamlMap)['path'] == spec.destination,
            orElse: () => fail('missing write_files entry ${spec.destination}'),
          ) as YamlMap;
          expect(entry['owner'], spec.owner);
          expect(entry['permissions'], spec.permissions);
          expect(entry['content'], service.sources[spec.source]);
        }
      });
    }
  });

  test('substitutes placeholders into file contents', () {
    final qdrant = seed.byId('qdrant_v1')!;
    final rendered =
        renderServiceCloudInit(qdrant, variables: {'api_key': 's3cret'});
    final config = loadYaml(rendered) as YamlMap;
    final env = (config['write_files'] as YamlList).firstWhere(
      (entry) => (entry as YamlMap)['path'] == '/opt/qdrant/qdrant.env',
    ) as YamlMap;

    expect(env['content'], contains('QDRANT__SERVICE__API_KEY=s3cret'));
    expect(env['content'], isNot(contains('{{api_key}}')));
  });

  test('injects gateway CA before growpart and marketplace runcmd', () {
    const pem = '-----BEGIN CERTIFICATE-----\nMIIBdemo\n-----END CERTIFICATE-----\n';
    final rendered = renderServiceCloudInit(
      fixtureService(id: 'demo_v1'),
      gatewayCaPem: pem,
    );
    final config = loadYaml(rendered) as YamlMap;

    expect(config['packages'], contains('ca-certificates'));
    final runcmd = config['runcmd'] as YamlList;
    expect(runcmd.first, gatewayCaUpdateRuncmd);
    expect(runcmd[1].toString(), contains('growpart'));

    final writeFiles = config['write_files'] as YamlList;
    final ca = writeFiles.firstWhere(
      (entry) => (entry as YamlMap)['path'] == gatewayCaGuestPath,
    ) as YamlMap;
    expect(ca['owner'], 'root:root');
    expect(ca['permissions'], '0644');
    expect(ca['content'], pem);
  });

  test('skips gateway CA inject without a PEM', () {
    final rendered = renderServiceCloudInit(fixtureService(id: 'demo_v1'));
    final config = loadYaml(rendered) as YamlMap;
    expect(config['packages'], isNot(contains('ca-certificates')));
    expect(
      (config['runcmd'] as YamlList).first.toString(),
      contains('growpart'),
    );
    expect(config['write_files'], isNull);
  });

  test('filling every parameter leaves no placeholders behind', () {
    for (final service in seed.services) {
      if (service.variables.isEmpty) continue;

      final rendered = renderServiceCloudInit(
        service,
        variables: {
          for (final variable in service.variables)
            variable.name: 'set-${variable.name}',
        },
      );

      for (final variable in service.variables) {
        expect(
          rendered,
          isNot(contains('{{${variable.name}}}')),
          reason: '${service.id} did not substitute ${variable.name}',
        );
        expect(rendered, contains('set-${variable.name}'));
      }
      expect(loadYaml(rendered), isA<YamlMap>());
    }
  });

  test('leaves non-parameter braces alone', () {
    final caddy = fixtureService(
      id: 'caddy_ca_v1',
      extraFiles: {
        'files/collect.sh':
            'echo {{.Service}}\ngrep -v \'{{\'\nCA_PEERS={{ca_peers}}\n',
      },
    );
    expect(caddy.variables.map((v) => v.name), ['ca_peers']);

    final rendered = renderServiceCloudInit(
      caddy,
      variables: {for (final v in caddy.variables) v.name: 'x'},
    );
    expect(rendered, contains('{{.Service}}'));
    expect(rendered, contains(r"grep -v '{{'"));
  });

  test('accepts parameter values that need YAML quoting', () {
    final qdrant = seed.byId('qdrant_v1')!;
    const awkward = "key: value # not a comment\n\ttabbed 'quoted'";

    final config = loadYaml(
      renderServiceCloudInit(qdrant, variables: {'api_key': awkward}),
    ) as YamlMap;
    final env = (config['write_files'] as YamlList).firstWhere(
      (entry) => (entry as YamlMap)['path'] == '/opt/qdrant/qdrant.env',
    ) as YamlMap;

    expect(env['content'], contains(awkward));
  });

  test('leaves placeholders intact when no variables are given', () {
    final qdrant = seed.byId('qdrant_v1')!;
    final config = loadYaml(renderServiceCloudInit(qdrant)) as YamlMap;
    final env = (config['write_files'] as YamlList).firstWhere(
      (entry) => (entry as YamlMap)['path'] == '/opt/qdrant/qdrant.env',
    ) as YamlMap;

    expect(env['content'], contains('{{api_key}}'));
  });

  group('cloud-config emitter', () {
    test('keeps strings that look like other types quoted', () {
      final yaml = emitCloudConfig({
        'permissions': '0600',
        'version': '1.10',
        'enabled': 'yes',
        'nothing': 'null',
        'flag': true,
        'count': 7,
        'absent': null,
      });
      final parsed = loadYaml(yaml) as YamlMap;

      expect(parsed['permissions'], '0600');
      expect(parsed['version'], '1.10');
      expect(parsed['enabled'], 'yes');
      expect(parsed['nothing'], 'null');
      expect(parsed['flag'], isTrue);
      expect(parsed['count'], 7);
      expect(parsed['absent'], isNull);
    });

    test('round-trips awkward scalars', () {
      const values = [
        '-p',
        '*glob',
        '{{placeholder}}',
        'key: value',
        '#hash',
        'trailing:',
        '',
        '@at',
        'has # comment',
        '  padded  ',
      ];
      final parsed = loadYaml(emitCloudConfig({'items': values})) as YamlMap;
      expect((parsed['items'] as YamlList).toList(), values);
    });

    test('round-trips multi-line content with varied trailing newlines', () {
      const values = [
        'one\ntwo\n',
        'one\ntwo',
        'one\n\n\n',
        'first\n  indented\nlast\n',
        '\nleading blank\n',
        '  indented first line\nsecond\n',
        'has\ttab\nand more\n',
      ];
      final parsed = loadYaml(emitCloudConfig({'items': values})) as YamlMap;
      expect((parsed['items'] as YamlList).toList(), values);
    });

    test('round-trips nested lists as used by runcmd', () {
      final config = {
        'runcmd': [
          ['mkdir', '-p', '/opt/x'],
          'systemctl enable --now docker.service',
        ],
      };
      final parsed = loadYaml(emitCloudConfig(config)) as YamlMap;
      final runcmd = parsed['runcmd'] as YamlList;

      expect((runcmd.first as YamlList).toList(), ['mkdir', '-p', '/opt/x']);
      expect(runcmd.last, 'systemctl enable --now docker.service');
    });

    test('emits empty collections in flow style', () {
      final parsed = loadYaml(
        emitCloudConfig({'list': <Object?>[], 'map': <String, Object?>{}}),
      ) as YamlMap;

      expect(parsed['list'], isEmpty);
      expect(parsed['map'], isEmpty);
    });
  });
}
