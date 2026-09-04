import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../brand.dart';
import 'resource_meter.dart';

/// Circular capacity ring for the Home system rail.
class CircularResourceGauge extends StatelessWidget {
  const CircularResourceGauge({
    required this.label,
    required this.valueText,
    required this.progress,
    this.placeholder = false,
    this.size = 72,
    this.color,
    super.key,
  });

  final String label;
  final String valueText;
  final double progress;
  final bool placeholder;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final clamped = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    final fill = placeholder
        ? onSurface.withValues(alpha: 0.22)
        : (color ?? ResourceMeter.fillFor(clamped));
    final pctLabel = placeholder
        ? '—'
        : '${(clamped * 100).round()}%';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: placeholder ? 0 : clamped,
              fill: fill,
              track: onSurface.withValues(alpha: 0.12),
              strokeWidth: size * 0.1,
            ),
            child: Center(
              child: Text(
                pctLabel,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w700,
                  color: onSurface.withValues(alpha: placeholder ? 0.45 : 0.92),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          valueText,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 11,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.fill,
    required this.track,
    required this.strokeWidth,
  });

  final double progress;
  final Color fill;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    if (progress <= 0) return;
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.fill != fill ||
        oldDelegate.track != track ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
