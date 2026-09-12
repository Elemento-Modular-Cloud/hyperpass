import 'package:elp_gui/services/service_branding.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

MarketplaceService parseService({
  required String id,
  String? iconYaml,
  String? iconSvg,
  String? extraMetadata,
}) {
  final files = <String, String>{
    'service.yaml': '''
api_version: elemento.cloud/v1
kind: ServiceTemplate
metadata:
  name: $id
  display_name: Demo
  version: 1.0.0
  description: A demo service
${extraMetadata ?? ''}${iconYaml ?? ''}cloud_init:
  entrypoint: cloud-init.yaml
prerequisites:
  resources:
    min_cpu: 1
    min_memory_gb: 1
''',
    'cloud-init.yaml': '#cloud-config\n',
  };
  if (iconSvg != null) {
    files['icon.svg'] = iconSvg;
  }
  return MarketplaceService.fromBundleEntry({
    'id': id,
    'files': files,
  });
}

void main() {
  test('resolves Font Awesome 6 solid names from marketplace manifests', () {
    expect(fontAwesomeIconForName('diagram-project'),
        FontAwesomeIcons.diagramProject);
    expect(fontAwesomeIconForName('fa-database'), FontAwesomeIcons.database);
    expect(fontAwesomeIconForName('paper-plane'), FontAwesomeIcons.paperPlane);
    expect(fontAwesomeIconForName('shrimp'), FontAwesomeIcons.shrimp);
    expect(fontAwesomeIconForName('staff-snake'), FontAwesomeIcons.staffSnake);
    expect(fontAwesomeIconForName('unknown-icon'), isNull);
  });

  test('parses catalog hex colours from metadata.color', () {
    expect(parseCatalogColor('#4169E1'), const Color(0xFF4169E1));
    expect(parseCatalogColor('EA4B71'), const Color(0xFFEA4B71));
    expect(parseCatalogColor('#f00'), const Color(0xFFFF0000));
    expect(parseCatalogColor('not-a-color'), isNull);
    expect(parseCatalogColor(''), isNull);
  });

  test('uses the catalog SVG and Font Awesome fallback from metadata.icon', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"></svg>';
    final service = parseService(
      id: 'postgres_v2',
      iconYaml: '  icon:\n    svg: icon.svg\n    fontawesome: database\n',
      iconSvg: svg,
    );

    expect(service.icon?.svg, 'icon.svg');
    expect(service.icon?.fontAwesome, 'database');
    expect(service.iconSvg, svg);

    final branding = serviceBranding(service.id, service: service);
    expect(branding.svg, svg);
    expect(branding.icon, FontAwesomeIcons.database);
    expect(branding.accent, const Color(0xFF4169E1));
  });

  test('uses metadata.color over the family accent', () {
    final service = parseService(
      id: 'postgres_v2',
      extraMetadata: '  color: "#EA4B71"\n',
    );

    expect(service.color, '#EA4B71');
    final branding = serviceBranding(service.id, service: service);
    expect(branding.accent, const Color(0xFFEA4B71));
  });

  test('falls back to family branding when the catalog has no icon', () {
    final service = parseService(id: 'qdrant_v1');
    expect(service.icon, isNull);
    expect(service.iconSvg, isNull);

    final branding = serviceBranding(service.id, service: service);
    expect(branding.svg, isNull);
    expect(branding.icon, FontAwesomeIcons.cube);
  });

  test('lookup finds a later family release when the exact id is folded', () {
    final library = MarketplaceLibrary.parse('''
{
  "schema": 1,
  "source": {"repo": "https://example.test/repo.git", "commit": "abc"},
  "services": [
    {
      "id": "postgres_v1",
      "files": {
        "service.yaml": "api_version: elemento.cloud/v1\\nkind: ServiceTemplate\\nmetadata:\\n  name: postgres_v1\\n  display_name: PostgreSQL\\n  version: 1.0.0\\n  description: old\\n  icon:\\n    svg: icon.svg\\n    fontawesome: database\\ncloud_init:\\n  entrypoint: cloud-init.yaml\\nprerequisites:\\n  resources:\\n    min_cpu: 1\\n    min_memory_gb: 1\\n",
        "cloud-init.yaml": "#cloud-config\\n",
        "icon.svg": "<svg xmlns=\\"http://www.w3.org/2000/svg\\"></svg>"
      }
    },
    {
      "id": "postgres_v2",
      "files": {
        "service.yaml": "api_version: elemento.cloud/v1\\nkind: ServiceTemplate\\nmetadata:\\n  name: postgres_v2\\n  display_name: PostgreSQL\\n  version: 2.0.0\\n  description: new\\n  icon:\\n    svg: icon.svg\\n    fontawesome: database\\ncloud_init:\\n  entrypoint: cloud-init.yaml\\nprerequisites:\\n  resources:\\n    min_cpu: 1\\n    min_memory_gb: 1\\n",
        "cloud-init.yaml": "#cloud-config\\n",
        "icon.svg": "<svg xmlns=\\"http://www.w3.org/2000/svg\\"></svg>"
      }
    }
  ]
}
''');

    expect(library.byId('postgres_v1'), isNull);
    expect(library.lookup('postgres_v1')?.id, 'postgres_v2');
    expect(library.lookup('postgres_v1')?.iconSvg, contains('<svg'));
  });

  testWidgets('renders the official SVG when branding carries catalog art',
      (tester) async {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/></svg>';
    await tester.pumpWidget(
      MaterialApp(
        home: ServiceIconBadge(
          branding: const ServiceBranding(
            icon: FontAwesomeIcons.database,
            accent: Color(0xFF31648C),
            svg: svg,
          ),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(FaIcon), findsNothing);
  });

  testWidgets('renders the Font Awesome fallback without catalog art',
      (tester) async {
    const accent = Color(0xFF31648C);
    await tester.pumpWidget(
      const MaterialApp(
        home: ServiceIconBadge(
          branding: ServiceBranding(
            icon: FontAwesomeIcons.database,
            accent: accent,
          ),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(FaIcon), findsOneWidget);
    expect(tester.widget<FaIcon>(find.byType(FaIcon)).color, accent);

    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(ServiceIconBadge),
        matching: find.byType(Container),
      ),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, catalogAccentFill(accent));
    expect((decoration.border as Border).top.color, accent);
  });
}
