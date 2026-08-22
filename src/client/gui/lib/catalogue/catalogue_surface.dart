import 'package:flutter/material.dart';

import '../brand.dart';

/// Solid catalogue panel with an optional accent border (no glass/blur).
class CatalogueSurface extends StatelessWidget {
  const CatalogueSurface({
    required this.child,
    this.borderColor,
    this.borderWidth = 1,
    this.padding,
    this.backgroundColor,
    super.key,
  });

  final Widget child;
  final Color? borderColor;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final surface = backgroundColor ?? Theme.of(context).colorScheme.surface;
    final border = borderColor ?? Theme.of(context).dividerColor;
    final radius = BorderRadius.circular(Brand.radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: radius,
        border: Border.all(color: border, width: borderWidth),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}
