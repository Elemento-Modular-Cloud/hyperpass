import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class HostMetricSample {
  const HostMetricSample({
    required this.cpuPct,
    required this.memoryPct,
    this.networkInBps = 0,
    this.networkOutBps = 0,
  });

  final double cpuPct;
  final double memoryPct;
  final double networkInBps;
  final double networkOutBps;
}

class HostMetricsHistoryNotifier extends Notifier<Queue<HostMetricSample>> {
  static const depth = 40;

  int? _prevRx;
  int? _prevTx;
  DateTime? _prevAt;

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
      final now = DateTime.now();
      final rx = data.networkRxBytes.toInt();
      final tx = data.networkTxBytes.toInt();

      var inBps = 0.0;
      var outBps = 0.0;
      final prevAt = _prevAt;
      final prevRx = _prevRx;
      final prevTx = _prevTx;
      if (prevAt != null && prevRx != null && prevTx != null) {
        final dtSec = now.difference(prevAt).inMilliseconds / 1000.0;
        if (dtSec > 0) {
          if (rx >= prevRx) inBps = (rx - prevRx) / dtSec;
          if (tx >= prevTx) outBps = (tx - prevTx) / dtSec;
        }
      }
      _prevAt = now;
      _prevRx = rx;
      _prevTx = tx;

      final sample = HostMetricSample(
        cpuPct: (data.cpuUsagePermille / 10).clamp(0, 100).toDouble(),
        memoryPct: memory == 0
            ? 0
            : (100.0 * used / memory).clamp(0, 100).toDouble(),
        networkInBps: inBps,
        networkOutBps: outBps,
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
