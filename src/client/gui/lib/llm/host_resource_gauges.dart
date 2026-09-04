import 'package:flutter/material.dart' hide Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../tooltip.dart';
import '../widgets/core_allocation_graph.dart';
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
        final usedHost = data.memoryUsedHost.toInt();
        final diskTotal = data.diskTotal.toInt() > 0
            ? data.diskTotal.toInt()
            : data.availableSpace.toInt();
        final diskUsed = data.diskUsed.toInt();
        final hostPct = memory == 0 ? 0 : (100 * usedHost / memory).round();
        final cpuRatio = (data.cpuUsagePermille / 1000).clamp(0.0, 1.0);
        final cpuPctLabel = (data.cpuUsagePermille / 10).round().toString();
        final memProgress =
            memory == 0 ? 0.0 : (usedHost / memory).clamp(0.0, 1.0);
        final diskProgress =
            diskTotal == 0 ? 0.0 : (diskUsed / diskTotal).clamp(0.0, 1.0);
        final serviceNames = {
          for (final info in ref.watch(serviceInstanceInfosProvider)) info.name,
        };
        final claims = [
          for (final claim in data.claims)
            if (claim.cpus > 0)
              CoreClaimSlice(
                name: claim.name,
                kind: claim.kind,
                cpus: claim.cpus,
              ),
        ];
        final coreGraph = CoreAllocationGraph(
          hostCpus: data.cpus,
          claims: claims,
          serviceNames: serviceNames,
          compact: compact,
        );

        final cpuMeter = ResourceMeter(
          label: l10n.hostCpuLabel,
          valueText: '$cpuPctLabel%',
          progress: cpuRatio,
          icon: FontAwesomeIcons.microchip,
          compact: compact,
        );
        final ramMeter = ResourceMeter(
          label: l10n.hostMemoryLabel,
          valueText:
              '${formatResourceBytes('$usedHost')} / ${formatResourceBytes('$memory')}',
          progress: memProgress,
          icon: FontAwesomeIcons.memory,
          compact: compact,
        );
        final diskMeter = ResourceMeter(
          label: l10n.hostDiskLabel,
          valueText: diskTotal > 0
              ? '${formatResourceBytes('$diskUsed')} / ${formatResourceBytes('$diskTotal')}'
              : '—',
          progress: diskProgress,
          icon: FontAwesomeIcons.hardDrive,
          compact: compact,
        );

        final child = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.hostSystemResourcesTitle,
                    style: TextStyle(
                      fontFamily: Brand.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 10),
                  cpuMeter,
                  const SizedBox(height: 12),
                  ramMeter,
                  const SizedBox(height: 12),
                  diskMeter,
                  const SizedBox(height: 12),
                  coreGraph,
                ],
              )
            : _HostMetersPanel(
                title: l10n.hostSystemResourcesTitle,
                cpu: cpuMeter,
                ram: ramMeter,
                disk: diskMeter,
                coreGraph: coreGraph,
              );

        return Tooltip(
          message: l10n.hostPressureTooltip(hostPct.toString(), cpuPctLabel),
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
    required this.cpu,
    required this.ram,
    required this.disk,
    required this.coreGraph,
  });

  final String title;
  final Widget cpu;
  final Widget ram;
  final Widget disk;
  final Widget coreGraph;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final glass = context.glass;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: glass.panelUnderlay ?? glass.fill,
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
                Expanded(child: cpu),
                const SizedBox(width: 16),
                Expanded(child: ram),
                const SizedBox(width: 16),
                Expanded(child: disk),
              ],
            ),
            const SizedBox(height: 16),
            coreGraph,
          ],
        ),
      ),
    );
  }
}
