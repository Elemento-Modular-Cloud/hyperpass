import 'package:flutter/material.dart' as fl;

import 'brand.dart';

class Tooltip extends fl.StatelessWidget {
  final fl.Widget child;
  final String message;
  final bool visible;

  const Tooltip({
    super.key,
    required this.child,
    required this.message,
    this.visible = true,
  });

  @override
  fl.Widget build(fl.BuildContext context) {
    final theme = fl.Theme.of(context);
    final isDark = theme.brightness == fl.Brightness.dark;
    // Tooltips stay high-contrast: dark chip + light text in both themes.
    final background =
        isDark ? const fl.Color(0xff111111) : Brand.voidBlack;
    final foreground = Brand.crystalWhite;

    return fl.TooltipVisibility(
      visible: visible,
      child: fl.Tooltip(
        key: fl.Key(message),
        message: message,
        textAlign: fl.TextAlign.center,
        textStyle: fl.TextStyle(
          color: foreground,
          fontFamily: Brand.fontFamily,
          fontSize: 12,
        ),
        decoration: fl.BoxDecoration(
          color: background,
          borderRadius: fl.BorderRadius.circular(Brand.radius),
        ),
        child: child,
      ),
    );
  }
}
