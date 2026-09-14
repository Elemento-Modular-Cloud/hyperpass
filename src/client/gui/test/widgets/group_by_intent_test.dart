import 'package:elp_gui/l10n/app_localizations.dart';
import 'package:elp_gui/vm_table/group_by_intent.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sorts named intents first and No intent last', () {
    expect(
      sortedIntentGroupKeys(['zeta', '', 'alpha']),
      ['alpha', 'zeta', ''],
    );
    expect(intentGroupLabel(''), 'No intent');
    expect(intentGroupLabel('web'), 'web');
  });

  test('groups items by intent key', () {
    final grouped = groupItemsByIntent(
      [
        ('web', 'a'),
        ('', 'b'),
        ('web', 'c'),
        ('db', 'd'),
      ],
      (item) => item.$1,
    );
    expect(grouped['web']!.map((e) => e.$2), ['a', 'c']);
    expect(grouped['']!.map((e) => e.$2), ['b']);
    expect(grouped['db']!.map((e) => e.$2), ['d']);
  });

  testWidgets('switch toggles the shared group-by-intent preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: GroupByIntentSwitch()),
        ),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GroupByIntentSwitch)),
    );
    expect(container.read(groupByIntentProvider), isFalse);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pump();

    expect(container.read(groupByIntentProvider), isTrue);
  });
}
