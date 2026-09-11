import 'package:elp_gui/brand.dart';
import 'package:elp_gui/widgets/launchpad_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  testWidgets('primary, secondary, and destructive render their labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            LaunchPadButton.primary(
              onPressed: () {},
              child: const Text('Launch'),
            ),
            LaunchPadButton.secondary(
              onPressed: () {},
              child: const Text('Cancel'),
            ),
            LaunchPadButton.destructive(
              onPressed: () {},
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  test('primary style uses the logo orange scale', () {
    final style = LaunchPadButton.styleFor(
      LaunchPadButtonKind.primary,
      onSurface: Colors.white,
      outline: Colors.grey,
    );
    expect(style.backgroundColor!.resolve({}), Brand.primary);
    expect(
      style.backgroundColor!.resolve({WidgetState.hovered}),
      Brand.primaryHover,
    );
    expect(
      style.backgroundColor!.resolve({WidgetState.pressed}),
      Brand.primaryActive,
    );
  });
}
