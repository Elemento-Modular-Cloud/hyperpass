import 'package:flutter/material.dart';

import 'brand.dart';
import 'catalogue/catalogue_surface.dart';

/// Full-page readable surface over wallpapers (Electros content cards).
///
/// Opacity matches sidebar and cards via [GlassPanel]'s shared panel underlay
/// unless [baseColor] is set (e.g. opaque [GlassTokens.cardSolid]).
class PageSurface extends StatelessWidget {
  const PageSurface({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(28, 24, 28, 24),
    this.margin = const EdgeInsets.fromLTRB(24, 24, 24, 20),
    this.baseColor,
    this.role = SurfaceRole.panel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? baseColor;
  final SurfaceRole role;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: CatalogueSurface(
        padding: padding,
        baseColor: baseColor,
        role: role,
        child: child,
      ),
    );
  }
}
