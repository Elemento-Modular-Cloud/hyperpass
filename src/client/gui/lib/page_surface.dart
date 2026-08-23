import 'package:flutter/material.dart';

import 'catalogue/catalogue_surface.dart';

/// Full-page readable surface over wallpapers (Electros content cards).
class PageSurface extends StatelessWidget {
  const PageSurface({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(28, 24, 28, 24),
    this.margin = const EdgeInsets.fromLTRB(24, 24, 24, 20),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: CatalogueSurface(
        padding: padding,
        child: child,
      ),
    );
  }
}
