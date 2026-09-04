import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../tooltip.dart';
import '../widgets/resource_meter.dart';

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
        final ramProgress =
            capacity == 0 ? 0.0 : (claimed / capacity).clamp(0.0, 1.0);
        final cpuProgress =
            data.cpus == 0 ? 0.0 : (data.cpusClaimed / data.cpus).clamp(0.0, 1.0);

        final ramMeter = ResourceMeter(
          label: l10n.hostRamScheduler,
          valueText:
              '${formatResourceBytes('$claimed')} / ${formatResourceBytes('$capacity')}',
          progress: ramProgress,
          icon: FontAwesomeIcons.memory,
          compact: compact,
        );
        final cpuMeter = ResourceMeter(
          label: l10n.hostCpuScheduler,
          valueText: '${data.cpusClaimed} / ${data.cpus}',
          progress: cpuProgress,
          icon: FontAwesomeIcons.microchip,
          compact: compact,
        );

        final child = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ramMeter,
                  const SizedBox(height: 12),
                  cpuMeter,
                ],
              )
            : _HostMetersPanel(
                title: l10n.vmTableHostPressure,
                ram: ramMeter,
                cpu: cpuMeter,
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

class _HostMetersPanel extends StatelessWidget {
  const _HostMetersPanel({
    required this.title,
    required this.ram,
    required this.cpu,
  });

  final String title;
  final Widget ram;
  final Widget cpu;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final glass = context.glass;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: glass.cardSolid.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: onSurface.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: ram),
                const SizedBox(width: 20),
                Expanded(child: cpu),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
