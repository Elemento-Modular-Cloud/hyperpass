import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpass_gui/l10n/app_localizations.dart';
import 'package:hyperpass_gui/services/service_cloud_init.dart';
import 'package:hyperpass_gui/services/service_library.dart';
import 'package:hyperpass_gui/services/service_parameters_form.dart';
import 'package:yaml/yaml.dart';

void main() {
  final library = MarketplaceLibrary.parse(
    File('assets/marketplace_services.json').readAsStringSync(),
  );

  late ServiceParameterEditors editors;

  Widget buildForm(MarketplaceService service) {
    editors = ServiceParameterEditors(service.variables);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ServiceParametersForm(editors: editors),
        ),
      ),
    );
  }

  tearDown(() => editors.dispose());

  testWidgets('renders a field for every parameter a service declares', (
    tester,
  ) async {
    final litellm = library.byId('litellm_v1')!;
    await tester.pumpWidget(buildForm(litellm));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(25));
    expect(find.text('25 optional settings · Anything left blank is '
        'generated inside the VM on first boot.'), findsOneWidget);

    // Labelled by the env key each placeholder fills.
    expect(find.text('LITELLM_MASTER_KEY'), findsOneWidget);
    expect(find.text('OPENAI_API_KEY'), findsOneWidget);
    expect(find.text('DATABASE_URL'), findsOneWidget);
  });

  testWidgets('shows the service authors documentation as helper text', (
    tester,
  ) async {
    await tester.pumpWidget(buildForm(library.byId('qdrant_v1')!));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('QDRANT__SERVICE__API_KEY'), findsOneWidget);
    expect(
      find.text('API key for REST / dashboard. '
          'Generated on first boot when left as a placeholder.'),
      findsOneWidget,
    );
    expect(find.text('generated'), findsOneWidget);
  });

  testWidgets('collects only the fields the user filled in', (tester) async {
    final litellm = library.byId('litellm_v1')!;
    await tester.pumpWidget(buildForm(litellm));
    await tester.pumpAndSettle();

    expect(editors.values, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'OPENAI_API_KEY'),
      'sk-test-123',
    );
    // Whitespace-only input counts as untouched.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'ANTHROPIC_API_KEY'),
      '   ',
    );
    await tester.pumpAndSettle();

    expect(editors.values, {'openai_api_key': 'sk-test-123'});
  });

  testWidgets('entered values reach the rendered cloud-init', (tester) async {
    final litellm = library.byId('litellm_v1')!;
    await tester.pumpWidget(buildForm(litellm));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'LITELLM_MASTER_KEY'),
      'sk-master',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'OPENAI_API_KEY'),
      'sk-openai',
    );
    await tester.pumpAndSettle();

    final config = loadYaml(
      renderServiceCloudInit(litellm, variables: editors.values),
    ) as YamlMap;
    final env = (config['write_files'] as YamlList).firstWhere(
      (entry) => (entry as YamlMap)['path'] == '/opt/litellm/litellm.env',
    ) as YamlMap;
    final content = env['content'] as String;

    expect(content, contains('LITELLM_MASTER_KEY=sk-master'));
    expect(content, contains('OPENAI_API_KEY=sk-openai'));
    // Untouched parameters stay as placeholders for the guest to generate.
    expect(content, contains('GEMINI_API_KEY={{gemini_api_key}}'));
  });

  testWidgets('renders nothing for a service without parameters', (
    tester,
  ) async {
    final npm = library.byId('npm_v1')!;
    expect(npm.variables, isEmpty);

    await tester.pumpWidget(buildForm(npm));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Parameters'), findsNothing);
  });
}
