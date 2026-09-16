import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../brand.dart';
import '../service_spec.dart';

const composePinBulletSize = 16.0;

/// Palette tab 0 = services, 1 = VMs, 2 = LLMs.
Color composeWorkloadTabColor(int index) {
  return switch (index) {
    1 => Brand.workloadVm,
    2 => Brand.workloadAi,
    _ => Brand.workloadService,
  };
}

Color get composeHttpOutputColor => Brand.info;

/// Services / VMs / LLMs tabs tinted with the resource-monitor workload colors.
class ComposeWorkloadTabBar extends StatelessWidget {
  const ComposeWorkloadTabBar({
    required this.controller,
    required this.servicesLabel,
    required this.vmsLabel,
    required this.llmsLabel,
    this.isScrollable = false,
    super.key,
  });

  final TabController controller;
  final String servicesLabel;
  final String vmsLabel;
  final String llmsLabel;
  final bool isScrollable;

  @override
  Widget build(BuildContext context) {
    final selected = controller.index;
    final indicator = composeWorkloadTabColor(selected);
    return TabBar(
      controller: controller,
      isScrollable: isScrollable,
      tabAlignment:
          isScrollable ? TabAlignment.start : TabAlignment.fill,
      labelColor: indicator,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: indicator, width: 3),
      ),
      tabs: [
        Tab(child: _tabLabel(servicesLabel, 0, selected)),
        Tab(child: _tabLabel(vmsLabel, 1, selected)),
        Tab(child: _tabLabel(llmsLabel, 2, selected)),
      ],
    );
  }

  Widget _tabLabel(String text, int index, int selected) {
    final color = composeWorkloadTabColor(index);
    return Text(
      text,
      style: TextStyle(
        color: index == selected ? color : color.withValues(alpha: 0.55),
        fontFamily: Brand.fontFamily,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

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
    this.http = false,
    super.key,
  });

  final Color color;
  final bool multiple;
  final bool lit;
  final bool http;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(composePinBulletSize),
      painter: ComposePinBulletPainter(
        color: color,
        multiple: multiple,
        lit: lit,
        http: http,
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
    this.http = false,
  });

  final Color color;
  final bool multiple;
  final bool lit;
  final bool http;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - (lit ? 1.5 : 0.6);

    if (http) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2.5));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: 0.16)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }

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
        oldDelegate.http != http ||
        oldDelegate.surface != surface;
  }
}
