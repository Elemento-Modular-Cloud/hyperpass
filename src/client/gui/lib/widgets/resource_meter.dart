import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';

/// Colored share of a [ResourceMeter] fill (e.g. VM / AI / service claims).
class ResourceMeterSegment {
  const ResourceMeterSegment({
    required this.color,
    required this.weight,
  });

  final Color color;
  final double weight;
}

/// Polished capacity meter used by host gauges and instance usage cells.
class ResourceMeter extends StatelessWidget {
  const ResourceMeter({
    required this.label,
    required this.valueText,
    required this.progress,
    this.icon,
    this.compact = false,
    this.showLabel = true,
    this.segments = const [],
    super.key,
  });

  final String label;
  final String valueText;
  final double progress;
  final IconData? icon;
  final bool compact;
  final bool showLabel;
  final List<ResourceMeterSegment> segments;

  static const warningThreshold = 0.8;
  static const criticalThreshold = 0.92;

  static Color fillFor(double progress) {
    if (progress >= criticalThreshold) return const Color(0xFFE35D6A);
    if (progress >= warningThreshold) return Brand.accentDark;
    return Brand.accent;
  }

  /// Builds VM / AI / service segments from scheduler claim weights.
  static List<ResourceMeterSegment> workloadSegments({
    required Iterable<({String name, String kind, double weight})> claims,
    required Set<String> serviceNames,
  }) {
    var vm = 0.0;
    var ai = 0.0;
    var service = 0.0;
    for (final claim in claims) {
      if (claim.weight <= 0) continue;
      final kind = serviceNames.contains(claim.name) || claim.kind == 'service'
          ? 'service'
          : claim.kind;
      switch (kind) {
        case 'llm':
          ai += claim.weight;
        case 'service':
          service += claim.weight;
        default:
          vm += claim.weight;
      }
    }
    return [
      if (vm > 0) ResourceMeterSegment(color: Brand.workloadVm, weight: vm),
      if (ai > 0) ResourceMeterSegment(color: Brand.workloadAi, weight: ai),
      if (service > 0)
        ResourceMeterSegment(color: Brand.workloadService, weight: service),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final clamped = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    final fill = fillFor(clamped);
    final trackHeight = compact ? 6.0 : 8.0;
    final labelSize = compact ? 11.0 : 12.0;
    final valueSize = compact ? 11.0 : 12.0;

    final bar = _MeterBar(
      progress: clamped,
      fill: fill,
      segments: segments,
      height: trackHeight,
      trackColor: onSurface.withValues(alpha: compact ? 0.12 : 0.14),
    );

    if (!showLabel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          bar,
          if (valueText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              valueText,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: valueSize,
                fontWeight: FontWeight.w500,
                color: onSurface.withValues(alpha: 0.85),
                height: 1.1,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              FaIcon(
                icon,
                size: compact ? 10 : 11,
                color: Brand.accent.withValues(alpha: 0.9),
              ),
              SizedBox(width: compact ? 6 : 8),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: labelSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: onSurface.withValues(alpha: 0.72),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              valueText,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: valueSize,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: onSurface.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 6 : 8),
        bar,
      ],
    );
  }
}

class _MeterBar extends StatelessWidget {
  const _MeterBar({
    required this.progress,
    required this.fill,
    required this.segments,
    required this.height,
    required this.trackColor,
  });

  final double progress;
  final Color fill;
  final List<ResourceMeterSegment> segments;
  final double height;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final active = [
      for (final segment in segments)
        if (segment.weight > 0) segment,
    ];
    final totalWeight =
        active.fold<double>(0, (sum, segment) => sum + segment.weight);

    final fillChild = active.isEmpty || totalWeight <= 0
        ? DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  fill.withValues(alpha: 0.85),
                  fill,
                ],
              ),
            ),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final segment in active)
                Expanded(
                  flex: (segment.weight / totalWeight * 1000)
                      .round()
                      .clamp(1, 1000000),
                  child: ColoredBox(color: segment.color),
                ),
            ],
          );

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              // FractionallySizedBox only tightens width; expand so the fill
              // keeps the track height (DecoratedBox/Row otherwise size to 0).
              child: SizedBox.expand(child: fillChild),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: 0.45,
                child: SizedBox.expand(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.18),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats byte counts for meter value labels.
String formatResourceBytes(String data) {
  const divider = 1024;
  const units = {
    'TiB': divider * divider * divider * divider,
    'GiB': divider * divider * divider,
    'MiB': divider * divider,
    'KiB': divider,
  };

  final size = int.tryParse(data) ?? 0;
  for (final MapEntry(key: suffix, value: unit) in units.entries) {
    if (size >= unit) return '${(size / unit).toStringAsFixed(1)}$suffix';
  }
  return '${size}B';
}

/// Formats a throughput in bytes/sec for sparkline value labels.
String formatResourceRate(double bytesPerSecond) {
  final bps = bytesPerSecond.isFinite ? bytesPerSecond.clamp(0, double.infinity) : 0.0;
  const divider = 1024.0;
  if (bps >= divider * divider * divider) {
    return '${(bps / (divider * divider * divider)).toStringAsFixed(1)} GiB/s';
  }
  if (bps >= divider * divider) {
    return '${(bps / (divider * divider)).toStringAsFixed(1)} MiB/s';
  }
  if (bps >= divider) {
    return '${(bps / divider).toStringAsFixed(1)} KiB/s';
  }
  return '${bps.round()} B/s';
}
