import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';

class OverviewMetricTile extends StatelessWidget {
  const OverviewMetricTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.baseColor,
    this.onTap,
    this.tooltip,
    this.muted = false,
    this.width = 148,
    this.expand = false,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final Color baseColor;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool muted;
  final double width;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final glass = context.glass;
    final child = Material(
      color: glass.panelUnderlay ?? baseColor,
      borderRadius: BorderRadius.circular(Brand.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Container(
          width: expand ? null : width,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            border: Border.all(color: onSurface.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FaIcon(
                icon,
                size: 14,
                color: muted ? iconColor.withValues(alpha: 0.55) : iconColor,
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: onSurface.withValues(alpha: muted ? 0.55 : 0.95),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 11,
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}
