import 'package:flutter/material.dart';

import '../brand.dart';
import 'launchpad_button.dart';

class CardAction {
  const CardAction({
    required this.label,
    required this.onTap,
    this.kind = LaunchPadButtonKind.secondary,
  });

  final String label;
  final VoidCallback? onTap;
  final LaunchPadButtonKind kind;
}

/// Full-width catalog-card footer matching the original segmented action bar.
class CardActionRow extends StatelessWidget {
  const CardActionRow({
    required this.actions,
    super.key,
  });

  final List<CardAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    final onSurface = Theme.of(context).colorScheme.onSurface;
    final error = Theme.of(context).colorScheme.error;
    final divider = Theme.of(context).dividerColor;
    final radius = BorderRadius.circular(Brand.radius);

    Widget segment(CardAction action, BorderRadius borderRadius) {
      final filled = action.kind == LaunchPadButtonKind.primary;
      final destructive = action.kind == LaunchPadButtonKind.destructive;
      final color = filled ? Brand.primary : Colors.transparent;
      final enabled = action.onTap != null;
      final textColor = (filled
              ? Brand.voidBlack
              : destructive
                  ? error
                  : onSurface)
          .withValues(alpha: enabled ? 1 : 0.38);

      return Expanded(
        child: Material(
          color: color,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: action.onTap,
            borderRadius: borderRadius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: filled
                    ? null
                    : Border(top: BorderSide(color: divider)),
                borderRadius: borderRadius,
              ),
              child: Center(
                child: Text(
                  action.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 12,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) Container(width: 1, color: divider),
            segment(
              actions[i],
              i == 0 && i == actions.length - 1
                  ? BorderRadius.only(
                      bottomLeft: radius.bottomLeft,
                      bottomRight: radius.bottomRight,
                    )
                  : i == 0
                      ? BorderRadius.only(bottomLeft: radius.bottomLeft)
                      : i == actions.length - 1
                          ? BorderRadius.only(bottomRight: radius.bottomRight)
                          : BorderRadius.zero,
            ),
          ],
        ],
      ),
    );
  }
}
