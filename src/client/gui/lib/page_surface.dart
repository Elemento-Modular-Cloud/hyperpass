import 'package:flutter/material.dart';

import 'brand.dart';
import 'catalogue/catalogue_surface.dart';
import 'layout/compact_layout.dart';

/// Full-page readable surface over wallpapers (Electros content cards).
///
/// Opacity matches sidebar and cards via [GlassPanel]'s shared panel underlay
/// unless [baseColor] is set (e.g. opaque [GlassTokens.cardSolid]).
class PageSurface extends StatelessWidget {
  const PageSurface({
    required this.child,
    this.padding,
    this.margin,
    this.baseColor,
    this.role = SurfaceRole.panel,
    super.key,
  });

  static const defaultPadding = EdgeInsets.fromLTRB(28, 24, 28, 24);
  static const defaultMargin = EdgeInsets.fromLTRB(24, 24, 24, 20);
  static const compactPadding = EdgeInsets.fromLTRB(16, 12, 16, 12);
  static const compactMargin = EdgeInsets.fromLTRB(12, 12, 12, 12);

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? baseColor;
  final SurfaceRole role;

  @override
  Widget build(BuildContext context) {
    final compact = CompactScope.of(context);
    return Padding(
      padding: margin ?? (compact ? compactMargin : defaultMargin),
      child: CatalogueSurface(
        padding: padding ?? (compact ? compactPadding : defaultPadding),
        baseColor: baseColor,
        role: role,
        child: child,
      ),
    );
  }
}

