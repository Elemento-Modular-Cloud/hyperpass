import 'package:flutter/material.dart';

import '../brand.dart';
import '../glass_panel.dart';

/// Glass catalogue / settings card (Electros `data-card` / `.card`).
class CatalogueSurface extends StatelessWidget {
  const CatalogueSurface({
    required this.child,
    this.borderColor,
    this.borderWidth = 1,
    this.padding,
    this.baseColor,
    this.role = SurfaceRole.card,
    super.key,
  });

  final Widget child;
  final Color? borderColor;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  /// Opaque underlay so text stays readable over wallpapers.
  final Color? baseColor;
  final SurfaceRole role;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final border = borderColor ?? glass.border;

    return GlassPanel(
      border: Border.all(color: border, width: borderWidth),
      padding: padding,
      baseColor: baseColor,
      role: role,
      child: child,
    );
  }
}
