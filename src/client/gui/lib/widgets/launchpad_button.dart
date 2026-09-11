import 'package:flutter/material.dart';

import '../brand.dart';

enum LaunchPadButtonKind { primary, secondary, destructive }

/// Three-tier LaunchPad button: primary (orange), secondary (bordered),
/// destructive (restrained red).
class LaunchPadButton extends StatelessWidget {
  const LaunchPadButton._({
    required this.kind,
    required this.onPressed,
    required this.child,
    this.compact = false,
    this.icon,
    this.expanded = false,
    super.key,
  });

  factory LaunchPadButton.primary({
    Key? key,
    required VoidCallback? onPressed,
    required Widget child,
    bool compact = false,
    IconData? icon,
    bool expanded = false,
  }) {
    return LaunchPadButton._(
      key: key,
      kind: LaunchPadButtonKind.primary,
      onPressed: onPressed,
      compact: compact,
      icon: icon,
      expanded: expanded,
      child: child,
    );
  }

  factory LaunchPadButton.secondary({
    Key? key,
    required VoidCallback? onPressed,
    required Widget child,
    bool compact = false,
    IconData? icon,
    bool expanded = false,
  }) {
    return LaunchPadButton._(
      key: key,
      kind: LaunchPadButtonKind.secondary,
      onPressed: onPressed,
      compact: compact,
      icon: icon,
      expanded: expanded,
      child: child,
    );
  }

  factory LaunchPadButton.destructive({
    Key? key,
    required VoidCallback? onPressed,
    required Widget child,
    bool compact = false,
    IconData? icon,
    bool expanded = false,
  }) {
    return LaunchPadButton._(
      key: key,
      kind: LaunchPadButtonKind.destructive,
      onPressed: onPressed,
      compact: compact,
      icon: icon,
      expanded: expanded,
      child: child,
    );
  }

  final LaunchPadButtonKind kind;
  final VoidCallback? onPressed;
  final Widget child;
  final bool compact;
  final IconData? icon;
  final bool expanded;

  static ButtonStyle styleFor(
    LaunchPadButtonKind kind, {
    required Color onSurface,
    required Color outline,
    bool compact = false,
  }) {
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    final textStyle = TextStyle(
      fontFamily: Brand.fontFamily,
      fontSize: compact ? 12 : 16,
      fontWeight: compact ? FontWeight.w600 : FontWeight.w500,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Brand.radius),
    );

    return switch (kind) {
      LaunchPadButtonKind.primary => ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Brand.primary.withValues(alpha: 0.35);
            }
            if (states.contains(WidgetState.pressed)) return Brand.primaryActive;
            if (states.contains(WidgetState.hovered)) return Brand.primaryHover;
            return Brand.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Brand.voidBlack.withAlpha(128);
            }
            return Brand.voidBlack;
          }),
          padding: WidgetStateProperty.all(padding),
          minimumSize: WidgetStateProperty.all(
            Size(compact ? 0 : 64, compact ? 32 : 44),
          ),
          tapTargetSize:
              compact ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
          visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
          shape: WidgetStateProperty.all(shape),
          textStyle: WidgetStateProperty.all(textStyle),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: Brand.primary, width: 2);
            }
            return BorderSide.none;
          }),
        ),
      LaunchPadButtonKind.secondary => ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return onSurface.withValues(alpha: 0.10);
            }
            if (states.contains(WidgetState.hovered)) {
              return onSurface.withValues(alpha: 0.06);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return onSurface.withAlpha(128);
            }
            return onSurface;
          }),
          padding: WidgetStateProperty.all(padding),
          minimumSize: WidgetStateProperty.all(
            Size(compact ? 0 : 64, compact ? 32 : 44),
          ),
          tapTargetSize:
              compact ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
          visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
          shape: WidgetStateProperty.all(shape),
          textStyle: WidgetStateProperty.all(textStyle),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: Brand.primary, width: 2);
            }
            return BorderSide(color: outline);
          }),
        ),
      LaunchPadButtonKind.destructive => ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Brand.destructive.withValues(alpha: 0.35);
            }
            if (states.contains(WidgetState.pressed)) {
              return const Color(0xFFA01224);
            }
            if (states.contains(WidgetState.hovered)) {
              return const Color(0xFFD41C33);
            }
            return Brand.destructive;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Brand.crystalWhite.withAlpha(128);
            }
            return Brand.crystalWhite;
          }),
          padding: WidgetStateProperty.all(padding),
          minimumSize: WidgetStateProperty.all(
            Size(compact ? 0 : 64, compact ? 32 : 44),
          ),
          tapTargetSize:
              compact ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
          visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
          shape: WidgetStateProperty.all(shape),
          textStyle: WidgetStateProperty.all(textStyle),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: Brand.primary, width: 2);
            }
            return BorderSide.none;
          }),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final outline =
        theme.brightness == Brightness.dark ? Brand.greyBody : const Color(0xff333333);
    final style = styleFor(
      kind,
      onSurface: onSurface,
      outline: outline,
      compact: compact,
    );

    final label = icon == null
        ? child
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 14 : 18),
              SizedBox(width: compact ? 6 : 8),
              Flexible(child: child),
            ],
          );

    final button = switch (kind) {
      LaunchPadButtonKind.primary || LaunchPadButtonKind.destructive => TextButton(
          onPressed: onPressed,
          style: style,
          child: label,
        ),
      LaunchPadButtonKind.secondary => OutlinedButton(
          onPressed: onPressed,
          style: style,
          child: label,
        ),
    };

    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
