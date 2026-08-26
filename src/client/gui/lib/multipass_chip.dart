import 'package:flutter/material.dart';

import 'brand.dart';
import 'daemon_source.dart';

/// Compact source badge shown next to Multipass-backed instance names.
class DaemonSourceChip extends StatelessWidget {
  final DaemonSource source;

  const DaemonSourceChip(this.source, {super.key});

  @override
  Widget build(BuildContext context) {
    if (source != DaemonSource.multipass) {
      return const SizedBox.shrink();
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: onSurface.withValues(alpha: 0.35)),
        color: onSurface.withValues(alpha: 0.06),
      ),
      child: Text(
        'Multipass',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: onSurface.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
