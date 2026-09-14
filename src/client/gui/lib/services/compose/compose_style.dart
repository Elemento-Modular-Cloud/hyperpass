import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../brand.dart';
import '../service_spec.dart';

const composePinBulletSize = 16.0;

const _contractPalette = <Color>[
  Brand.workloadAi,
  Brand.info,
  Brand.workloadVm,
  Brand.workloadService,
  Brand.warning,
  Brand.primary,
  Color(0xFF4ECDC4),
  Color(0xFFE07A5F),
];

/// Stable color for a contract so pins and edges of the same kind match.
Color composeContractColor(String contract) {
  switch (contract) {
    case openaiCompatibleContract:
      return Brand.workloadAi;
    case caddyCaContract:
      return Brand.info;
    case 'qdrant':
      return Brand.workloadVm;
    case 'n8n_sandbox':
      return Brand.primary;
    default:
      var hash = 0;
      for (final unit in contract.codeUnits) {
        hash = 0x1fffffff & (hash * 31 + unit);
      }
      return _contractPalette[hash.abs() % _contractPalette.length];
  }
}

class ComposePinBullet extends StatelessWidget {
  const ComposePinBullet({
    required this.color,
    required this.multiple,
    this.lit = false,
    super.key,
  });

  final Color color;
  final bool multiple;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(composePinBulletSize),
      painter: ComposePinBulletPainter(
        color: color,
        multiple: multiple,
        lit: lit,
        surface: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}

class ComposePinBulletPainter extends CustomPainter {
  ComposePinBulletPainter({
    required this.color,
    required this.multiple,
    required this.lit,
    required this.surface,
  });

  final Color color;
  final bool multiple;
  final bool lit;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - (lit ? 1.5 : 0.6);

    if (multiple) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: 0.16),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
      const pipRadius = 2.15;
      final orbit = radius * 0.42;
      for (var i = 0; i < 3; i++) {
        final angle = -math.pi / 2 + i * 2 * math.pi / 3;
        final pip = center + Offset(math.cos(angle), math.sin(angle)) * orbit;
        canvas.drawCircle(pip, pipRadius + 0.7, Paint()..color = surface);
        canvas.drawCircle(pip, pipRadius, Paint()..color = color);
      }
    } else {
      canvas.drawCircle(center, radius, Paint()..color = color);
    }

    if (lit) {
      canvas.drawCircle(
        center,
        radius + 1.6,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ComposePinBulletPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.multiple != multiple ||
        oldDelegate.lit != lit ||
        oldDelegate.surface != surface;
  }
}
