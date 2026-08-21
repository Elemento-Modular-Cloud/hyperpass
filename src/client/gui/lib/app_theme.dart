import 'package:flutter/material.dart';

import 'brand.dart';
import 'vm_details/mapping_slider.dart';

ThemeData buildAppTheme({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final scaffold = isDark ? Brand.black : Brand.white;
  final onSurface = isDark ? Brand.greyBody : Brand.greyDarker;
  final surface = isDark ? Brand.blackLight : Brand.whiteLight;
  final inputFill =
      isDark ? Colors.white.withOpacity(0.08) : const Color(0xfff2f2f2);
  final outline = isDark ? Brand.blackLight : const Color(0xff333333);
  final glass = isDark ? GlassTokens.dark : GlassTokens.light;

  return ThemeData(
    useMaterial3: false,
    brightness: brightness,
    fontFamily: Brand.fontFamily,
    fontFamilyFallback: const ['NotoColorEmoji', 'FreeSans'],
    scaffoldBackgroundColor: scaffold,
    canvasColor: scaffold,
    cardColor: surface,
    dividerColor: isDark ? Brand.blackLight : const Color(0xffe0e0e0),
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: Brand.yellow,
      onPrimary: Brand.voidBlack,
      secondary: Brand.yellowDark,
      onSecondary: Brand.voidBlack,
      error: const Color(0xffC7162B),
      onError: Brand.crystalWhite,
      surface: surface,
      onSurface: onSurface,
    ),
    extensions: [glass],
    inputDecorationTheme: InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      fillColor: inputFill,
      filled: true,
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(width: 2, color: onSurface),
        borderRadius: BorderRadius.zero,
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(width: 2, color: onSurface.withAlpha(80)),
        borderRadius: BorderRadius.zero,
      ),
      isDense: true,
      suffixIconColor: onSurface,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        disabledForegroundColor: onSurface.withAlpha(128),
        foregroundColor: onSurface,
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
        ),
        side: BorderSide(color: outline),
        textStyle: const TextStyle(fontFamily: Brand.fontFamily, fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        backgroundColor: Brand.yellow,
        disabledForegroundColor: Brand.voidBlack.withAlpha(128),
        foregroundColor: Brand.voidBlack,
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
        ),
        textStyle: const TextStyle(fontFamily: Brand.fontFamily, fontSize: 16),
      ),
    ),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      bodyMedium: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      bodySmall: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      titleLarge: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      titleMedium: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      titleSmall: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      labelLarge: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      displayLarge: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      displayMedium: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      displaySmall: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      headlineLarge: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      headlineMedium: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
      headlineSmall: TextStyle(color: onSurface, fontFamily: Brand.fontFamily),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: onSurface,
      selectionColor: Brand.yellow.withAlpha(100),
    ),
    tabBarTheme: TabBarThemeData(
      indicator: BoxDecoration(
        color: isDark ? Colors.white12 : Colors.black12,
        border: Border(bottom: BorderSide(width: 3, color: onSurface)),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: onSurface,
      labelStyle: const TextStyle(
        fontFamily: Brand.fontFamily,
        fontWeight: FontWeight.bold,
      ),
      unselectedLabelColor: onSurface,
      unselectedLabelStyle: const TextStyle(
        fontFamily: Brand.fontFamily,
        fontWeight: FontWeight.bold,
      ),
      tabAlignment: TabAlignment.start,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: Brand.yellow,
      inactiveTrackColor:
          isDark ? Brand.blackLight : const Color(0xffd9d9d9),
      overlayShape: SliderComponentShape.noThumb,
      thumbColor: Brand.crystalWhite,
      thumbShape: CustomThumbShape(),
      tickMarkShape: SliderTickMarkShape.noTickMark,
      trackHeight: 2,
      trackShape: CustomTrackShape(),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Brand.yellow;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Brand.voidBlack),
      side: BorderSide(color: onSurface),
    ),
  );
}

final lightTheme = buildAppTheme(brightness: Brightness.light);
final darkTheme = buildAppTheme(brightness: Brightness.dark);
