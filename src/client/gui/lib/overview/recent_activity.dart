import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class RecentActivityEvent {
  const RecentActivityEvent({
    required this.title,
    required this.detail,
    required this.at,
  });

  final String title;
  final String detail;
  final DateTime at;
}

class RecentActivityNotifier extends Notifier<List<RecentActivityEvent>> {
  static const maxEvents = 40;

  @override
  List<RecentActivityEvent> build() => const [];

  void record({required String title, String detail = ''}) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final at = DateTime.now();
    final event = RecentActivityEvent(
      title: trimmed,
      detail: detail.trim().isEmpty
          ? DateFormat.Hm().format(at)
          : detail.trim(),
      at: at,
    );
    state = [event, ...state].take(maxEvents).toList(growable: false);
  }
}

final recentActivityProvider =
    NotifierProvider<RecentActivityNotifier, List<RecentActivityEvent>>(
  RecentActivityNotifier.new,
);
