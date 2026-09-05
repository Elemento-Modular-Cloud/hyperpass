import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elp_gui/l10n/app_localizations.dart';
import 'package:elp_gui/services/service_library.dart';
import 'package:elp_gui/services/services_screen.dart';

/// `rootBundle` never completes under `flutter test`, so the library is read
/// from disk and injected. Asset delivery is covered by
/// `service_cloud_init_test.dart`, which checks the pubspec declaration.
MarketplaceLibrary loadLibraryFromDisk() {
  return MarketplaceLibrary.parse(
    File('assets/marketplace_services.json').readAsStringSync(),
  );
}

Finder findCard(String serviceId) => find.byWidgetPredicate(
      (widget) => widget is ServiceCard && widget.service.id == serviceId,
    );

void main() {
  final library = loadLibraryFromDisk();

  Widget buildScreen() {
    return ProviderScope(
      overrides: [
        marketplaceLibraryProvider.overrideWith((ref) => library),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ServicesScreen(),
      ),
    );
  }

  /// Filters down to one service and opens its detail page.
  Future<void> openDetail(WidgetTester tester, String query, String id) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: findCard(id), matching: find.text('Details')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows one card per service, newest release only', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byType(ServiceCard), findsNWidgets(16));
    expect(find.text('Qdrant'), findsOneWidget);
    expect(find.text('MinIO'), findsOneWidget);

    // Only n8n_v3 survives, so the shared display name appears once.
    expect(find.text('n8n Workflow Automation'), findsOneWidget);
    expect(findCard('n8n_v3'), findsOneWidget);
    expect(findCard('n8n_v2'), findsNothing);
    expect(findCard('n8n'), findsNothing);
  });

  testWidgets('search matches names and descriptions', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'minio');
    await tester.pumpAndSettle();
    expect(find.byType(ServiceCard), findsOneWidget);
    expect(findCard('minio_v1'), findsOneWidget);

    // Qdrant is also named in the n8n and Open WebUI descriptions.
    await tester.enterText(find.byType(TextField), 'qdrant');
    await tester.pumpAndSettle();
    expect(find.byType(ServiceCard), findsNWidgets(3));
    expect(findCard('qdrant_v1'), findsOneWidget);
    expect(findCard('minio_v1'), findsNothing);
  });

  testWidgets('shows an empty state when nothing matches', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nothing-matches-this');
    await tester.pumpAndSettle();

    expect(find.byType(ServiceCard), findsNothing);
    expect(find.text('No services match your search'), findsOneWidget);
  });

  testWidgets('detail page reports manifest requirements', (tester) async {
    await openDetail(tester, 'minio', 'minio_v1');

    expect(find.byType(ServiceCard), findsNothing);
    expect(find.text('minio_v1 · Version 1.0.0'), findsOneWidget);
    expect(find.text('Requirements'), findsOneWidget);
    expect(find.text('2 vCPUs'), findsOneWidget);
    expect(find.text('2 GiB RAM'), findsOneWidget);
    // 5 GiB base disk on top of the 20 GiB the manifest wants to persist.
    expect(find.text('25 GiB disk'), findsOneWidget);
    expect(find.text('Ingress ports'), findsOneWidget);
    expect(find.text('443'), findsOneWidget);

    await tester.tap(find.text('All services'));
    await tester.pumpAndSettle();

    expect(find.byType(ServiceCard), findsOneWidget);
  });

  testWidgets('detail page lists the parameters a service accepts', (
    tester,
  ) async {
    await openDetail(tester, 'qdrant', 'qdrant_v1');

    expect(find.text('qdrant_v1 · Version 1.1.0'), findsOneWidget);
    expect(find.text('6 files written to the VM'), findsOneWidget);
    expect(find.text('Parameters'), findsOneWidget);
    expect(
      find.text('1 optional setting · Anything left blank is generated '
          'inside the VM on first boot.'),
      findsOneWidget,
    );
    // Labelled by the setting it fills, with the authors' own note.
    expect(find.text('QDRANT__SERVICE__API_KEY'), findsOneWidget);
    expect(
      find.text('API key for REST / dashboard. '
          'Generated on first boot when left as a placeholder.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the cloud-init a service would deploy with', (
    tester,
  ) async {
    await openDetail(tester, 'qdrant', 'qdrant_v1');

    await tester.tap(find.text('View cloud-init'));
    await tester.pumpAndSettle();

    expect(find.text('Qdrant cloud-init'), findsOneWidget);

    final rendered = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(SelectableText),
    );
    expect(rendered, findsOneWidget);

    final yaml = tester.widget<SelectableText>(rendered).data!;
    expect(yaml, startsWith('#cloud-config\n'));
    expect(yaml, contains('path: /opt/qdrant/docker-compose.yml'));
    // Root growth is injected by the renderer, not by the service recipe.
    expect(yaml, contains('resize_rootfs: true'));
  });
}
