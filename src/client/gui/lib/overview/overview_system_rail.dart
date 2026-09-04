import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';
import '../catalogue/catalogue_surface.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/core_allocation_graph.dart';
import '../widgets/resource_meter.dart';
import 'host_metrics_history.dart';

class OverviewSystemRail extends ConsumerWidget {
  const OverviewSystemRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final glass = context.glass;
    final daemon = ref.watch(daemonInfoProvider).asData?.value;
    final daemonUp = ref.watch(daemonAvailableProvider);
    final multipass = ref.watch(multipassSidebarStatusProvider);
    final healthy = daemonUp &&
        (multipass == MultipassSidebarStatus.online ||
            multipass == MultipassSidebarStatus.hidden ||
            multipass == MultipassSidebarStatus.disabled);
    final history = ref.watch(hostMetricsHistoryProvider);

    final memory = daemon?.memory.toInt() ?? 0;
    final usedHost = daemon?.memoryUsedHost.toInt() ?? 0;
    final cpus = daemon?.cpus ?? 0;
    final claimedCpus = daemon?.cpusClaimed ?? 0;
    final cpuPct =
        daemon == null ? 0.0 : (daemon.cpuUsagePermille / 1000).clamp(0.0, 1.0);
    final memPct = memory == 0 ? 0.0 : (usedHost / memory).clamp(0.0, 1.0);
    final diskTotal = daemon == null
        ? 0
        : (daemon.diskTotal.toInt() > 0
            ? daemon.diskTotal.toInt()
            : daemon.availableSpace.toInt());
    final diskUsed = daemon?.diskUsed.toInt() ?? 0;
    final diskPct =
        diskTotal == 0 ? 0.0 : (diskUsed / diskTotal).clamp(0.0, 1.0);
    final memAvail = math.max(0, memory - usedHost);
    final diskAvail = math.max(0, diskTotal - diskUsed);
    final cpuAvailPct = ((1.0 - cpuPct) * 100).clamp(0, 100).round();
    final coresAvail = math.max(0, cpus - claimedCpus);
    final serviceNames = {
      for (final info in ref.watch(serviceInstanceInfosProvider)) info.name,
    };
    final claims = [
      for (final claim in daemon?.claims ?? const [])
        if (claim.cpus > 0)
          CoreClaimSlice(
            name: claim.name,
            kind: claim.kind,
            cpus: claim.cpus,
          ),
    ];

    final hostName = daemon?.hostName.isNotEmpty == true
        ? daemon!.hostName
        : l10n.overviewHostUnknown;
    final hostOs = daemon?.hostOs ?? '';
    final hostArch = daemon?.hostArch ?? '';
    final uptime = _formatUptime(daemon?.hostUptimeSeconds.toInt() ?? 0, l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogueSurface(
          baseColor: glass.cardSolid.withValues(alpha: 0.5),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.overviewSystemTitle,
                      style: TextStyle(
                        fontFamily: Brand.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: onSurface,
                      ),
                    ),
                  ),
                  _HealthyBadge(healthy: healthy),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                hostName,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (hostOs.isNotEmpty) hostOs,
                  if (hostArch.isNotEmpty) hostArch,
                ].join(' · '),
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 12,
                  color: onSurface.withValues(alpha: 0.65),
                ),
              ),
              if (uptime.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  l10n.overviewHostUptime(uptime),
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 12,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _ResourceRow(
                label: l10n.overviewGaugeCpu,
                percent: (cpuPct * 100).round(),
                detail: '$claimedCpus / $cpus vCPU',
                color: Brand.accent,
              ),
              const SizedBox(height: 10),
              _ResourceRow(
                label: l10n.overviewGaugeMemory,
                percent: (memPct * 100).round(),
                detail:
                    '${formatResourceBytes('$usedHost')} / ${formatResourceBytes('$memory')}',
                color: Brand.yellowLight,
              ),
              const SizedBox(height: 10),
              _ResourceRow(
                label: l10n.overviewGaugeDisk,
                percent: (diskPct * 100).round(),
                detail: diskTotal > 0
                    ? '${formatResourceBytes('$diskUsed')} / ${formatResourceBytes('$diskTotal')}'
                    : '—',
                color: const Color(0xFF6CB6FF),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.overviewAvailableCapacityTitle,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 10),
              _CapacityLine(
                label: l10n.overviewGaugeCpu,
                value: l10n.overviewCapacityPctAvailable(cpuAvailPct),
              ),
              _CapacityLine(
                label: l10n.overviewGaugeMemory,
                value: l10n.overviewCapacityBytesAvailable(
                  formatResourceBytes('$memAvail'),
                ),
              ),
              _CapacityLine(
                label: l10n.overviewGaugeDisk,
                value: l10n.overviewCapacityBytesAvailable(
                  formatResourceBytes('$diskAvail'),
                ),
              ),
              _CapacityLine(
                label: l10n.overviewCapacityVmLabel,
                value: l10n.overviewCapacityVmAvailable(coresAvail, cpus),
              ),
              _CapacityLine(
                label: l10n.overviewCapacityAcceleratorLabel,
                value: l10n.overviewCapacityAcceleratorUnavailable,
              ),
              const SizedBox(height: 16),
              CoreAllocationGraph(
                hostCpus: cpus,
                claims: claims,
                serviceNames: serviceNames,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CatalogueSurface(
          baseColor: glass.cardSolid.withValues(alpha: 0.5),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.overviewActivityPanelTitle,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _SparkRow(
                label: l10n.overviewGaugeCpu,
                values: history.map((s) => s.cpuPct).toList(),
                color: Brand.accent,
                valueLabel: history.isEmpty
                    ? '—'
                    : '${history.last.cpuPct.round()}%',
              ),
              const SizedBox(height: 10),
              _SparkRow(
                label: l10n.overviewGaugeMemory,
                values: history.map((s) => s.memoryPct).toList(),
                color: Brand.yellowLight,
                valueLabel: formatResourceBytes('$usedHost'),
              ),
              const SizedBox(height: 10),
              _SparkRow(
                label: l10n.overviewNetworkIn,
                values: const [],
                color: Brand.accent,
                placeholder: true,
                valueLabel: '↓ ${l10n.overviewNetworkComingSoonValue}',
              ),
              const SizedBox(height: 10),
              _SparkRow(
                label: l10n.overviewNetworkOut,
                values: const [],
                color: onSurface.withValues(alpha: 0.5),
                placeholder: true,
                valueLabel: '↑ ${l10n.overviewNetworkComingSoonValue}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CatalogueSurface(
          baseColor: glass.cardSolid.withValues(alpha: 0.5),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: _RecentActivityPanel(
            // Event store not wired yet — keep empty shell ready for ≤4 items.
            events: const [],
          ),
        ),
      ],
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.label,
    required this.percent,
    required this.detail,
    required this.color,
  });

  final String label;
  final int percent;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            Text(
              '$percent%',
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          style: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 11,
            color: onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: onSurface.withValues(alpha: 0.1),
            color: color,
          ),
        ),
      ],
    );
  }
}

class _CapacityLine extends StatelessWidget {
  const _CapacityLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 12,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparkRow extends StatelessWidget {
  const _SparkRow({
    required this.label,
    required this.values,
    required this.color,
    required this.valueLabel,
    this.placeholder = false,
  });

  final String label;
  final List<double> values;
  final Color color;
  final String valueLabel;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final spots = values.isEmpty
        ? <FlSpot>[const FlSpot(0, 0), const FlSpot(1, 0)]
        : [
            for (var i = 0; i < values.length; i++)
              FlSpot(i.toDouble(), values[i]),
          ];

    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 11,
              color: onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 28,
            child: Opacity(
              opacity: placeholder ? 0.35 : 1,
              child: LineChart(
                duration: Duration.zero,
                LineChartData(
                  borderData: FlBorderData(show: false),
                  clipData: const FlClipData.all(),
                  gridData: const FlGridData(show: false),
                  maxY: 100,
                  minY: 0,
                  lineBarsData: [
                    LineChartBarData(
                      barWidth: 1.5,
                      color: color,
                      dotData: const FlDotData(show: false),
                      spots: spots,
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                  lineTouchData: const LineTouchData(enabled: false),
                  titlesData: const FlTitlesData(show: false),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
              color: onSurface.withValues(alpha: placeholder ? 0.4 : 0.8),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentActivityEvent {
  const _RecentActivityEvent({
    required this.title,
    required this.detail,
  });

  final String title;
  final String detail;
}

class _RecentActivityPanel extends StatelessWidget {
  const _RecentActivityPanel({required this.events});

  static const maxVisible = 4;

  final List<_RecentActivityEvent> events;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final visible = events.take(maxVisible).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.overviewActivityTitle,
          style: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
        ),
        if (visible.isEmpty) ...[
          const SizedBox(height: 16),
          FaIcon(
            FontAwesomeIcons.clockRotateLeft,
            size: 18,
            color: onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.overviewActivityEmptyTitle,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.overviewActivityEmptyBody,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 12,
              height: 1.4,
              color: onSurface.withValues(alpha: 0.55),
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          for (final event in visible) ...[
            Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              event.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 11,
                color: onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {},
              child: Text(l10n.overviewActivityViewAll),
            ),
          ),
        ],
      ],
    );
  }
}

class _HealthyBadge extends StatelessWidget {
  const _HealthyBadge({required this.healthy});

  final bool healthy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = healthy ? Brand.green : Brand.accentDark;
    final label =
        healthy ? l10n.overviewStatusHealthy : l10n.overviewStatusDegraded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatUptime(int seconds, AppLocalizations l10n) {
  if (seconds <= 0) return '';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final mins = (seconds % 3600) ~/ 60;
  if (days > 0) return l10n.overviewUptimeDaysHours(days, hours);
  if (hours > 0) return l10n.overviewUptimeHoursMins(hours, mins);
  return l10n.overviewUptimeMins(mins);
}
