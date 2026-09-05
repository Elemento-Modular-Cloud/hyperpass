import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:elp_gui/services/service_cloud_init.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:yaml/yaml.dart';

/// Set this to a directory to dump every rendered service, so the output can
/// be diffed against the elemento-marketplace Python renderer:
///   MARKETPLACE_RENDER_OUT=/tmp/dart-render flutter test test/services
const _outputDirVariable = 'MARKETPLACE_RENDER_OUT';

MarketplaceLibrary loadLibraryFromDisk() {
  final bundle = File('assets/marketplace_services.json');
  if (!bundle.existsSync()) {
    throw StateError(
      'Missing ${bundle.path}. '
      'Run scripts/sync-marketplace-services.py to generate the bundle.',
    );
  }
  return MarketplaceLibrary.parse(bundle.readAsStringSync());
}

void main() {
  final library = loadLibraryFromDisk();

  test('bundle is shipped as a Flutter asset', () {
    // `rootBundle` does not resolve under `flutter test`, so the delivery
    // contract is checked statically: the bundle must sit directly inside the
    // asset directory that pubspec.yaml declares.
    expect(File(marketplaceBundleAsset).existsSync(), isTrue);
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('\n    - assets/\n'),
    );
  });

  test('bundle exposes the service library', () {
    // 18 bundled directories collapse to 16 once superseded n8n releases drop.
    expect(library.services, hasLength(16));
    expect(library.commit, isNot('unknown'));

    final qdrant = library.byId('qdrant_v1')!;
    expect(qdrant.displayName, 'Qdrant');
    expect(qdrant.resources.minCpu, 2);
    expect(qdrant.resources.minMemoryGb, 4);
    expect(qdrant.totalStorageGb, 10);
    expect(qdrant.exposedPorts, [80, 443]);
    expect(qdrant.files, hasLength(6));
  });

  test('keeps only the newest release of each service', () {
    // n8n 1.0.0, n8n_v2 2.0.0 and n8n_v3 3.4.0 are one family.
    expect(library.byId('n8n_v3'), isNotNull);
    expect(library.byId('n8n_v2'), isNull);
    expect(library.byId('n8n'), isNull);

    // A differently named tool is not folded into the n8n family.
    expect(library.byId('n8n_runner_v1'), isNotNull);
    expect(serviceFamily('n8n_runner_v1'), 'n8n_runner');

    final displayNames = library.services.map((s) => s.displayName).toList();
    expect(displayNames, displayNames.toSet().toList());
  });

  test('discovers parameters with their setting name and docs', () {
    final qdrant = library.byId('qdrant_v1')!;
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

    // The busiest service keeps its env-file grouping rather than sorting.
    final litellm = library.byId('litellm_v1')!;
    expect(litellm.variables, hasLength(25));
    expect(litellm.variables.first.name, 'token');
    expect(litellm.variables.first.key, 'LITELLM_MASTER_KEY');
    expect(
      litellm.variables.map((v) => v.name).take(4),
      ['token', 'litellm_image', 'openai_api_key', 'openai_model'],
    );

    // Every discovered parameter is substitutable.
    for (final service in library.services) {
      for (final variable in service.variables) {
        expect(variable.name, isNotEmpty);
        expect(variable.sources, isNotEmpty);
      }
    }
  });

  group('renders every service', () {
    final outputDir = Platform.environment[_outputDirVariable];

    for (final service in library.services) {
      test(service.id, () {
        final rendered = renderServiceCloudInit(service);

        if (outputDir != null) {
          final file = File('$outputDir/${service.id}.yaml');
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(rendered);
        }

        expect(rendered, startsWith('#cloud-config\n'));

        final config = loadYaml(rendered) as YamlMap;

        // Root growth is injected for every service.
        expect(config['resize_rootfs'], isTrue);
        expect((config['growpart'] as YamlMap)['mode'], 'auto');
        expect(config['packages'], contains('cloud-guest-utils'));
        expect(
          (config['runcmd'] as YamlList).first.toString(),
          contains('growpart'),
        );

        // Manifest `files:` are folded into write_files verbatim.
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
    final qdrant = library.byId('qdrant_v1')!;
    final rendered =
        renderServiceCloudInit(qdrant, variables: {'api_key': 's3cret'});
    final config = loadYaml(rendered) as YamlMap;
    final env = (config['write_files'] as YamlList).firstWhere(
      (entry) => (entry as YamlMap)['path'] == '/opt/qdrant/qdrant.env',
    ) as YamlMap;

    expect(env['content'], contains('QDRANT__SERVICE__API_KEY=s3cret'));
    expect(env['content'], isNot(contains('{{api_key}}')));
  });

  test('filling every parameter leaves no placeholders behind', () {
    for (final service in library.services) {
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
      // Still valid cloud-config after substitution.
      expect(loadYaml(rendered), isA<YamlMap>());
    }
  });

  test('leaves non-parameter braces alone', () {
    // caddy_ca_v1 ships a Docker Go-template and a `grep -v '{{'` guard that
    // strips leftover placeholders on the guest. Neither is a parameter.
    final caddy = library.byId('caddy_ca_v1')!;
    expect(caddy.variables.map((v) => v.name), ['ca_peers', 'ca_refresh_seconds']);

    final rendered = renderServiceCloudInit(
      caddy,
      variables: {for (final v in caddy.variables) v.name: 'x'},
    );
    expect(rendered, contains('{{.Service}}'));
    expect(rendered, contains(r"grep -v '{{'"));
  });

  test('accepts parameter values that need YAML quoting', () {
    final qdrant = library.byId('qdrant_v1')!;
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
    final qdrant = library.byId('qdrant_v1')!;
    final config = loadYaml(renderServiceCloudInit(qdrant)) as YamlMap;
    final env = (config['write_files'] as YamlList).firstWhere(
      (entry) => (entry as YamlMap)['path'] == '/opt/qdrant/qdrant.env',
    ) as YamlMap;

    // configure-qdrant.sh generates a secret when it sees the placeholder.
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
