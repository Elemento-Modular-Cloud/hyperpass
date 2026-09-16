import 'package:elp_gui/appearance_settings.dart';
import 'package:elp_gui/brand.dart';
import 'package:elp_gui/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _DarkAppearance extends AppearanceSettingsNotifier {
  @override
  AppearanceSettings build() =>
      const AppearanceSettings(theme: AppearanceTheme.dark);
}

void main() {
  testWidgets('sidebar section paints a tinted bento card', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appearanceSettingsProvider.overrideWith(_DarkAppearance.new),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: SidebarSection(
                label: 'Compute',
                accent: Brand.workloadVm,
                children: [
                  Text('Images'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Compute'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);

    final card = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(SidebarSection),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = card.decoration as BoxDecoration;
    expect(decoration.color, Brand.workloadVm.withValues(alpha: 0.16));
    expect(decoration.borderRadius, BorderRadius.circular(Brand.radius));
    expect(decoration.border, isNotNull);
  });
}
