import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../tooltip.dart';
import '../vm_details/memory_usage.dart';

class HostResourceGauges extends ConsumerWidget {
  final bool compact;
  const HostResourceGauges({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final info = ref.watch(daemonInfoProvider);
    return info.when(
      data: (data) {
        final memory = data.memory.toInt();
        final reserved = data.memoryReserved.toInt();
        final claimed = data.memoryClaimed.toInt();
        final usedHost = data.memoryUsedHost.toInt();
        final capacity = memory > reserved ? memory - reserved : memory;
        final hostPct = memory == 0 ? 0 : (100 * usedHost / memory).round();
        final cpuPct = (data.cpuUsagePermille / 10).toStringAsFixed(0);
        final ramBar = MemoryUsage(
          used: '$claimed',
          total: '$capacity',
        );
        final cpuValue = data.cpus == 0 ? 0.0 : data.cpusClaimed / data.cpus;
        final cpuBar = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: cpuValue.isFinite ? cpuValue.clamp(0.0, 1.0) : 0,
              backgroundColor: MemoryUsage.backgroundColor,
              color: cpuValue < 0.8 ? MemoryUsage.normalColor : MemoryUsage.almostFullColor,
            ),
            const SizedBox(height: 2),
            Text(
              '${data.cpusClaimed} / ${data.cpus}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface),
            ),
          ],
        );
        final child = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.hostRamScheduler, style: const TextStyle(fontSize: 11)),
                  ramBar,
                  const SizedBox(height: 6),
                  Text(l10n.hostCpuScheduler, style: const TextStyle(fontSize: 11)),
                  cpuBar,
                ],
              )
            : Row(
                children: [
                  Expanded(child: ramBar),
                  const SizedBox(width: 16),
                  Expanded(child: cpuBar),
                ],
              );
        return Tooltip(
          message: l10n.hostPressureTooltip(hostPct.toString(), cpuPct),
          child: child,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
