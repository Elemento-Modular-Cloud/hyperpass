import 'dart:ui';

import 'package:flutter/material.dart';

import 'brand.dart';

/// Glassmorphism panel matching ElectrosGUI `data-card` / `.card` recipe:
/// backdrop blur, translucent fill, soft border, inset highlight, radius 6.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final radius = BorderRadius.circular(Brand.radius);

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
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: Brand.glassBlurSigma,
            sigmaY: Brand.glassBlurSigma,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: glass.fill),
              ),
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
                        glass.fill.withOpacity(0),
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
                    border: Border.all(color: glass.border),
                  ),
                ),
              ),
              Padding(
                padding: padding ?? EdgeInsets.zero,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
