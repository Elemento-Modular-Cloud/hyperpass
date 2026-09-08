import 'dart:convert';
import 'dart:io';

import 'package:elp_gui/services/service_library.dart';

/// The last-resort catalog shipped in the app — not the live marketplace.
MarketplaceLibrary loadSeedLibrary() {
  final bundle = File(marketplaceSeedAsset);
  if (!bundle.existsSync()) {
    throw StateError('Missing ${bundle.path}');
  }
  return MarketplaceLibrary.parse(bundle.readAsStringSync());
}

MarketplaceService fixtureService({
  required String id,
  String displayName = 'Demo',
  String version = '1.0.0',
  String description = 'A demo service',
  String? iconFontAwesome,
  String? iconSvg,
  Map<String, String> extraFiles = const {},
  String cloudInit = '#cloud-config\npackages: []\n',
  List<String>? fileSources,
}) {
  final iconYaml = iconFontAwesome == null
      ? ''
      : '  icon:\n    svg: icon.svg\n    fontawesome: $iconFontAwesome\n';
  final declaredFiles = fileSources ?? extraFiles.keys.toList();
  final filesYaml = declaredFiles
      .map(
        (source) => '  - source: $source\n'
            '    destination: /opt/demo/${source.split('/').last}\n'
            '    owner: root:root\n'
            '    permissions: "0644"\n',
      )
      .join();

  final files = <String, String>{
    'service.yaml': '''
api_version: elemento.cloud/v1
kind: ServiceTemplate
metadata:
  name: $id
  display_name: $displayName
  version: $version
  description: $description
$iconYaml'''
        'cloud_init:\n'
        '  entrypoint: cloud-init.yaml\n'
        'prerequisites:\n'
        '  resources:\n'
        '    min_cpu: 1\n'
        '    min_memory_gb: 1\n'
        '${filesYaml.isEmpty ? '' : 'files:\n$filesYaml'}',
    'cloud-init.yaml': cloudInit,
    ...extraFiles,
  };
  if (iconSvg != null) {
    files['icon.svg'] = iconSvg;
  }

  return MarketplaceService.fromBundleEntry({
    'id': id,
    'files': files,
  });
}

MarketplaceLibrary fixtureLibrary(
  List<MarketplaceService> services, {
  String commit = 'test',
}) {
  return MarketplaceLibrary.parse(
    jsonEncode({
      'schema': 1,
      'source': {
        'repo': 'https://example.test/repo.git',
        'commit': commit,
      },
      'services': [
        for (final service in services)
          {'id': service.id, 'files': service.sources},
      ],
    }),
  );
}
