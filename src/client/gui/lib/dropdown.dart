import 'package:flutter/material.dart';

import 'brand.dart';

class Dropdown<T> extends StatelessWidget {
  final String? label;
  final T? value;
  final ValueChanged<T?> onChanged;
  final Map<T, String> items;
  final double width;

  const Dropdown({
    super.key,
    this.label,
    this.value,
    required this.onChanged,
    required this.items,
    this.width = 360,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final dropdown = DropdownButton<T>(
      icon: Icon(Icons.keyboard_arrow_down, color: onSurface),
      isDense: true,
      isExpanded: true,
      focusColor: Colors.transparent,
      dropdownColor: Theme.of(context).colorScheme.surface,
      style: TextStyle(
        color: onSurface,
        fontFamily: Brand.fontFamily,
        fontSize: 16,
      ),
      underline: const SizedBox.shrink(),
      value: value,
      onChanged: onChanged,
      items: items.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: TextStyle(color: onSurface)),
            ),
          )
          .toList(),
    );

    final styledDropdown = SizedBox(
      width: width,
      child: InputDecorator(
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
          ),
          child: dropdown,
        ),
      ),
    );

    return Row(
      children: [
        if (label != null) ...[
          Expanded(
            child: Text(
              label!,
              style: TextStyle(fontSize: 16, color: onSurface),
            ),
          ),
        ],
        styledDropdown,
      ],
    );
  }
}
