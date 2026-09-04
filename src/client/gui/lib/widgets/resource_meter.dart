import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';

/// Polished capacity meter used by host gauges and instance usage cells.
class ResourceMeter extends StatelessWidget {
  const ResourceMeter({
    required this.label,
    required this.valueText,
    required this.progress,
    this.icon,
    this.compact = false,
    this.showLabel = true,
    super.key,
  });

  final String label;
  final String valueText;
  final double progress;
  final IconData? icon;
  final bool compact;
  final bool showLabel;

  static const warningThreshold = 0.8;
  static const criticalThreshold = 0.92;

  static Color fillFor(double progress) {
    if (progress >= criticalThreshold) return const Color(0xFFE35D6A);
    if (progress >= warningThreshold) return Brand.accentDark;
    return Brand.accent;
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
      height: trackHeight,
      trackColor: onSurface.withValues(alpha: compact ? 0.12 : 0.14),
    );

    if (!showLabel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          bar,
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
    required this.height,
    required this.trackColor,
  });

  final double progress;
  final Color fill;
  final double height;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      fill.withValues(alpha: 0.85),
                      fill,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: fill.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
              ),
            ),
            // Soft top sheen for depth without looking like a toy gauge.
            Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: 0.45,
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
