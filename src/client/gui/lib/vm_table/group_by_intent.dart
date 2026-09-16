import 'package:flutter/material.dart' hide Table, Switch;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand.dart';
import '../switch.dart';
import 'table.dart';

class GroupByIntentNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    state = value;
  }
}

final groupByIntentProvider = NotifierProvider<GroupByIntentNotifier, bool>(
  GroupByIntentNotifier.new,
);

/// Empty intent sorts last so named groups come first.
List<String> sortedIntentGroupKeys(Iterable<String> keys) {
  final sorted = keys.toList()
    ..sort((a, b) {
      if (a.isEmpty || b.isEmpty) return a.isEmpty ? 1 : -1;
      return a.compareTo(b);
    });
  return sorted;
}

Map<String, List<T>> groupItemsByIntent<T>(
  Iterable<T> items,
  String Function(T) intentOf,
) {
  final groups = <String, List<T>>{};
  for (final item in items) {
    groups.putIfAbsent(intentOf(item), () => []).add(item);
  }
  return groups;
}

String intentGroupLabel(String intent) =>
    intent.isEmpty ? 'No composition' : intent;

class GroupByIntentSwitch extends ConsumerWidget {
  const GroupByIntentSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return UnconstrainedBox(
      constrainedAxis: Axis.vertical,
      child: Switch(
        label: 'Group by composition',
        value: ref.watch(groupByIntentProvider),
        onChanged: (v) => ref.read(groupByIntentProvider.notifier).set(v),
      ),
    );
  }
}

class IntentGroupHeading extends StatelessWidget {
  const IntentGroupHeading(this.intent, {super.key});

  final String intent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        intentGroupLabel(intent),
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One [Table] per intent (plus one for untagged rows), stacked in a
/// scrollable column. Each table is given an explicit height sized to its
/// row count, since [Table] (a 2D scrollable) needs a bounded height and
/// can't just be dropped into an unbounded-height [ListView].
class GroupedByIntentTables<T> extends StatelessWidget {
  const GroupedByIntentTables({
    super.key,
    required this.data,
    required this.headers,
    required this.intentOf,
    required this.isSelected,
    this.groupSelectAll,
    this.rowExtent = 50,
    this.headerRowHeight = 56,
  });

  final List<T> data;
  final List<TableHeader<T>> headers;
  final String Function(T) intentOf;
  final bool Function(T) isSelected;
  final Widget Function(List<T> group)? groupSelectAll;
  final double rowExtent;
  final double headerRowHeight;

  @override
  Widget build(BuildContext context) {
    final groups = groupItemsByIntent(data, intentOf);
    final sortedKeys = sortedIntentGroupKeys(groups.keys);
    if (sortedKeys.isEmpty) return const SizedBox.shrink();

    return ListView(
      children: [
        for (final key in sortedKeys) ...[
          IntentGroupHeading(key),
          SizedBox(
            height: headerRowHeight + groups[key]!.length * rowExtent,
            child: Table<T>(
              headers: [
                for (final h in headers)
                  if (h.name == 'checkbox' && groupSelectAll != null)
                    TableHeader<T>(
                      name: h.name,
                      childBuilder: (_) => groupSelectAll!(groups[key]!),
                      width: h.width,
                      minWidth: h.minWidth,
                      cellBuilder: h.cellBuilder,
                    )
                  else
                    h,
              ],
              data: groups[key]!,
              finalRow: const [],
              isSelected: isSelected,
              rowExtent: rowExtent,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
