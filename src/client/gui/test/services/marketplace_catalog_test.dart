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
      '  color: "#4169E1"\n'
      '  icon:\n'
      '    svg: icon.svg\n'
      '    fontawesome: database\n'
      'cloud_init:\n'
      '  entrypoint: cloud-init.yaml\n'
      'prerequisites:\n'
      '  resources:\n'
      '    min_cpu: 1\n'
      '    min_memory_gb: 1\n',
    );
    File('${service.path}/cloud-init.yaml')
        .writeAsStringSync('#cloud-config\n');
    File('${service.path}/icon.svg').writeAsStringSync(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"></svg>\n',
    );

    final bundle = await buildBundleFromServicesDir(
      root,
      commit: 'abc123',
      repo: marketplaceRepoUrl,
    );
    final library = MarketplaceLibrary.parse(serialiseBundle(bundle));

    expect(library.commit, 'abc123');
    expect(library.byId('demo_v1')?.displayName, 'Demo');
    expect(library.byId('demo_v1')?.color, '#4169E1');
    expect(library.byId('demo_v1')?.icon?.svg, 'icon.svg');
    expect(library.byId('demo_v1')?.icon?.fontAwesome, 'database');
    expect(library.byId('demo_v1')?.iconSvg, contains('<svg'));
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
  icon:
    svg: icon.svg
    fontawesome: cube
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
    archive.addFile(
      ArchiveFile.string(
        '$prefix/icon.svg',
        '<svg xmlns="http://www.w3.org/2000/svg"></svg>\n',
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
    expect(library.byId('demo_v1')?.iconSvg, contains('<svg'));
    expect(library.byId('demo_v1')?.icon?.fontAwesome, 'cube');
  });

  test('loads a direct JSON URL and caches it on disk', () async {
    final cacheDir =
        await Directory.systemTemp.createTemp('marketplace-cache-');
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

  test('resolves a clone root to its services/ directory', () async {
    final clone = await Directory.systemTemp.createTemp('marketplace-clone-');
    addTearDown(() => clone.delete(recursive: true));

    final services = Directory('${clone.path}/services')..createSync();
    final demo = Directory('${services.path}/demo_v1')..createSync();
    File('${demo.path}/service.yaml').writeAsStringSync(
      'api_version: elemento.cloud/v1\n'
      'kind: ServiceTemplate\n'
      'metadata:\n'
      '  name: demo_v1\n'
      '  display_name: From Clone\n'
      '  version: 1.0.0\n'
      '  description: Clone shaped\n'
      'cloud_init:\n'
      '  entrypoint: cloud-init.yaml\n'
      'prerequisites:\n'
      '  resources:\n'
      '    min_cpu: 1\n'
      '    min_memory_gb: 1\n',
    );
    File('${demo.path}/cloud-init.yaml').writeAsStringSync('#cloud-config\n');

    expect(
      resolveMarketplaceServicesDir(clone.path)?.path,
      services.path,
    );

    final catalog = MarketplaceCatalog(
      servicesDirectory: clone.path,
      bundleUrl: '',
    );
    final json = await catalog.loadJson();
    final library = MarketplaceLibrary.parse(json!);
    expect(library.byId('demo_v1')?.displayName, 'From Clone');

    File('${demo.path}/service.yaml').writeAsStringSync(
      'api_version: elemento.cloud/v1\n'
      'kind: ServiceTemplate\n'
      'metadata:\n'
      '  name: demo_v1\n'
      '  display_name: Edited Live\n'
      '  version: 1.0.1\n'
      '  description: Picked up on reload\n'
      'cloud_init:\n'
      '  entrypoint: cloud-init.yaml\n'
      'prerequisites:\n'
      '  resources:\n'
      '    min_cpu: 1\n'
      '    min_memory_gb: 1\n',
    );
    final reloaded = MarketplaceLibrary.parse((await catalog.loadJson())!);
    expect(reloaded.byId('demo_v1')?.displayName, 'Edited Live');
    expect(reloaded.byId('demo_v1')?.version, '1.0.1');
    catalog.close();
  });

  test('ignores git and editor paths when watching a checkout', () {
    expect(ignoreMarketplaceWatchPath('/tmp/repo/.git/HEAD'), isTrue);
    expect(ignoreMarketplaceWatchPath(r'C:\repo\.git\config'), isTrue);
    expect(ignoreMarketplaceWatchPath('/tmp/repo/services/n8n/service.yaml~'),
        isTrue);
    expect(
      ignoreMarketplaceWatchPath('/tmp/repo/services/n8n/service.yaml'),
      isFalse,
    );
  });
}
