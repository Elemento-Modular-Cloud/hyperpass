import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class HostMetricSample {
  const HostMetricSample({
    required this.cpuPct,
    required this.memoryPct,
  });

  final double cpuPct;
  final double memoryPct;
}

class HostMetricsHistoryNotifier extends Notifier<Queue<HostMetricSample>> {
  static const depth = 40;

  @override
  Queue<HostMetricSample> build() {
    final history = Queue.of(
      Iterable.generate(
        depth,
        (_) => const HostMetricSample(cpuPct: 0, memoryPct: 0),
      ),
    );

    ref.listen(daemonInfoProvider, (_, next) {
      final data = next.asData?.value;
      if (data == null) return;
      final memory = data.memory.toInt();
      final used = data.memoryUsedHost.toInt();
      final sample = HostMetricSample(
        cpuPct: (data.cpuUsagePermille / 10).clamp(0, 100).toDouble(),
        memoryPct: memory == 0
            ? 0
            : (100.0 * used / memory).clamp(0, 100).toDouble(),
      );
      state = Queue.of(state)
        ..removeFirst()
        ..addLast(sample);
    });

    return history;
  }
}

final hostMetricsHistoryProvider =
    NotifierProvider<HostMetricsHistoryNotifier, Queue<HostMetricSample>>(
  HostMetricsHistoryNotifier.new,
);
