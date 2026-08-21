import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Switch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  final bool trailingSwitch;
  final double size;
  final bool enabled;

  const Switch({
    super.key,
    required this.value,
    this.onChanged,
    this.label = '',
    this.trailingSwitch = false,
    this.size = 25,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final switchBox = SizedBox(
      height: size,
      child: FittedBox(
        child: CupertinoSwitch(
          activeTrackColor: CupertinoColors.activeBlue,
          inactiveTrackColor:
              isDark ? const Color(0xff555555) : const Color(0xffd9d9d9),
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );

    final labelText = Text(
      label,
      style: TextStyle(fontSize: 16, color: onSurface),
    );

    return trailingSwitch
        ? Row(
            children: [
              Expanded(child: labelText),
              const SizedBox(width: 8),
              switchBox,
            ],
          )
        : Row(children: [switchBox, const SizedBox(width: 8), labelText]);
  }
}
