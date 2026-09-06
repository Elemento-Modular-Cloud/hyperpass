import 'package:flutter/material.dart';

import '../brand.dart';
import '../catalogue/catalogue_surface.dart';

/// Rounded catalogue-style search field used across list and browse pages.
class RoundedSearchField extends StatelessWidget {
  const RoundedSearchField({
    required this.hint,
    required this.onChanged,
    this.controller,
    this.width = 280,
    super.key,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  /// When null, expands to the parent width (useful in full-bleed layouts).
  final double? width;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final field = CatalogueSurface(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          fontSize: 13,
          color: onSurface,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: onSurface.withValues(alpha: 0.45),
            fontFamily: Brand.fontFamily,
            fontSize: 13,
          ),
          // CatalogueSurface already provides fill + border; avoid nested
          // theme underlines that leave sharp inner seams.
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          isDense: true,
          filled: false,
          prefixIcon: Icon(
            Icons.search,
            color: onSurface.withValues(alpha: 0.5),
            size: 18,
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 32),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );

    if (width == null) return field;
    return SizedBox(width: width, child: field);
  }
}
