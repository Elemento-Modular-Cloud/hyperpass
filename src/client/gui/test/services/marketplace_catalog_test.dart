import 'dart:io';

import 'package:archive/archive.dart';
import 'package:elp_gui/services/marketplace_catalog.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('builds a bundle from a local services directory', () async {
    final root = await Directory.systemTemp.createTemp('marketplace-dir-');
    addTearDown(() => root.delete(recursive: true));

    final service = Directory('${root.path}/demo_v1')..createSync();
    File('${service.path}/service.yaml').writeAsStringSync(
      'api_version: elemento.cloud/v1\n'
      'kind: ServiceTemplate\n'
      'metadata:\n'
      '  name: demo_v1\n'
      '  display_name: Demo\n'
      '  version: 1.0.0\n'
      '  description: A demo service\n'
      'cloud_init:\n'
      '  entrypoint: cloud-init.yaml\n'
      'prerequisites:\n'
      '  resources:\n'
      '    min_cpu: 1\n'
      '    min_memory_gb: 1\n',
    );
    File('${service.path}/cloud-init.yaml').writeAsStringSync('#cloud-config\n');

    final bundle = await buildBundleFromServicesDir(
      root,
      commit: 'abc123',
      repo: marketplaceRepoUrl,
    );
    final library = MarketplaceLibrary.parse(serialiseBundle(bundle));

    expect(library.commit, 'abc123');
    expect(library.byId('demo_v1')?.displayName, 'Demo');
  });

  test('builds a bundle from a GitHub-style zipball', () {
    final archive = Archive();
    const prefix =
        'Elemento-Modular-Cloud-elemento-marketplace-deadbeef/services/demo_v1';
    archive.addFile(
      ArchiveFile.string(
        '$prefix/service.yaml',
        '''
api_version: elemento.cloud/v1
kind: ServiceTemplate
metadata:
  name: demo_v1
  display_name: Zipped
  version: 2.0.0
  description: From zip
cloud_init:
  entrypoint: cloud-init.yaml
prerequisites:
  resources:
    min_cpu: 1
    min_memory_gb: 1
''',
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        '$prefix/cloud-init.yaml',
        '#cloud-config\n',
      ),
    );

    final library = MarketplaceLibrary.parse(
      serialiseBundle(
        buildBundleFromZipArchive(
          archive,
          commit: 'deadbeef',
          repo: marketplaceRepoUrl,
        ),
      ),
    );

    expect(library.commit, 'deadbeef');
    expect(library.byId('demo_v1')?.displayName, 'Zipped');
  });

  test('loads a direct JSON URL and caches it on disk', () async {
    final cacheDir = await Directory.systemTemp.createTemp('marketplace-cache-');
    addTearDown(() => cacheDir.delete(recursive: true));

    const payload = '''
{
  "schema": 1,
  "source": {"repo": "https://example.test/repo.git", "commit": "cafebabe"},
  "services": [
    {
      "id": "url_v1",
      "files": {
        "service.yaml": "api_version: elemento.cloud/v1\\nkind: ServiceTemplate\\nmetadata:\\n  name: url_v1\\n  display_name: From URL\\n  version: 1.0.0\\n  description: Remote\\ncloud_init:\\n  entrypoint: cloud-init.yaml\\nprerequisites:\\n  resources:\\n    min_cpu: 1\\n    min_memory_gb: 1\\n",
        "cloud-init.yaml": "#cloud-config\\n"
      }
    }
  ]
}
''';

    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://example.test/marketplace.json');
      return http.Response(payload, 200);
    });

    final catalog = MarketplaceCatalog(
      httpClient: client,
      cacheDirectory: cacheDir,
      bundleUrl: 'https://example.test/marketplace.json',
      servicesDirectory: '', // disable env override
    );

    final json = await catalog.loadJson(forceRefresh: true);
    expect(json, isNotNull);
    final library = MarketplaceLibrary.parse(json!);
    expect(library.byId('url_v1')?.displayName, 'From URL');
    expect(
      File('${cacheDir.path}/marketplace_services.json').existsSync(),
      isTrue,
    );
    catalog.close();
  });
}
