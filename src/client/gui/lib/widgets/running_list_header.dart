import 'package:flutter/material.dart';

import '../brand.dart';

/// Shared chrome for the three “running workloads” list pages
/// (Instances / Running models / Deployments).
class RunningListHeader extends StatelessWidget {
  const RunningListHeader({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 37,
                  fontWeight: FontWeight.w300,
                  color: onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 16),
              action!,
            ],
          ],
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 14,
              height: 1.4,
              color: onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}
