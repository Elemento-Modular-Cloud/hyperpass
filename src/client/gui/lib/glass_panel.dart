import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'brand.dart';

/// Glassmorphism panel matching ElectrosGUI `data-card` / `.card` / `nav-bar`.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Border? border;
  final Color? baseColor;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.borderRadius,
    this.border,
    this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final blurSigma = context.appearanceTokens.blurSigma;
    final radius = borderRadius ?? BorderRadius.circular(Brand.radius);
    final edge = border ?? Border.all(color: glass.border);
    final useBlur = blurSigma > 0;

    Widget panel = Stack(
      children: [
        if (baseColor != null)
          Positioned.fill(
            child: ColoredBox(color: baseColor!),
          ),
        Positioned.fill(
          child: ColoredBox(color: glass.fill),
        ),
        if (useBlur)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: const Alignment(-0.8, -1),
                  end: const Alignment(1, 1),
                  colors: [
                    glass.gradientStart,
                    glass.gradientMid,
                    glass.fill.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: edge,
            ),
          ),
        ),
        Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ],
    );

    if (useBlur) {
      panel = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: panel,
      );
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: glass.shadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: panel,
      ),
    );
  }
}
