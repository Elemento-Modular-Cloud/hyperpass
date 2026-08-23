import 'package:flutter/material.dart';

import 'appearance_settings.dart';
import 'brand.dart';
import 'vm_details/mapping_slider.dart';

GlassTokens resolveGlassTokens(AppearanceSettings appearance) {
  final tokens = !appearance.useGlassmorphism
      ? GlassTokens.solid(
          colour: appearance.cardColorValue,
          opacityPercent: appearance.cardOpacity,
        )
      : switch (appearance.theme) {
          AppearanceTheme.light => GlassTokens.light,
          AppearanceTheme.dark => GlassTokens.dark,
          AppearanceTheme.highContrast => GlassTokens.highContrast,
        };
  return appearance.useGlassmorphism
      ? tokens.withRenderOpacityCompensation()
      : tokens;
}

ThemeData buildAppTheme(AppearanceSettings appearance) {
  final brightness = appearance.brightness;
  final isDark = brightness == Brightness.dark;
  final isHighContrast = appearance.theme == AppearanceTheme.highContrast;
  final onSurface = isDark ? Brand.crystalWhite : Brand.greyDarker;
  final surface = isHighContrast
      ? Colors.black
      : (isDark ? Brand.blackLight : Brand.whiteLight);
  final inputFill =
      isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xfff2f2f2);
  final outline = isDark ? Brand.greyBody : const Color(0xff333333);
  final glass = resolveGlassTokens(appearance);
  final blurSigma =
      appearance.useGlassmorphism ? Brand.glassBlurSigma : 0.0;

  return ThemeData(
    useMaterial3: false,
    brightness: brightness,
    fontFamily: Brand.fontFamily,
    fontFamilyFallback: const ['NotoColorEmoji', 'FreeSans'],
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    cardColor: surface,
    dividerColor: isDark ? Colors.white24 : const Color(0xffe0e0e0),
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: Brand.accent,
      onPrimary: Brand.crystalWhite,
      secondary: Brand.accentDark,
      onSecondary: Brand.crystalWhite,
      error: const Color(0xffC7162B),
      onError: Brand.crystalWhite,
      surface: surface,
      onSurface: onSurface,
    ),
    extensions: [glass, AppearanceTokens(blurSigma: blurSigma)],
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
        backgroundColor: Brand.accent,
        disabledForegroundColor: Brand.crystalWhite.withAlpha(128),
        foregroundColor: Brand.crystalWhite,
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
      selectionColor: Brand.accent.withAlpha(100),
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
      activeTrackColor: Brand.accent,
      inactiveTrackColor:
          isDark ? Colors.white24 : const Color(0xffd9d9d9),
      overlayShape: SliderComponentShape.noThumb,
      thumbColor: Brand.crystalWhite,
      thumbShape: CustomThumbShape(),
      tickMarkShape: SliderTickMarkShape.noTickMark,
      trackHeight: 2,
      trackShape: CustomTrackShape(),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Brand.accent;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Brand.crystalWhite),
      side: BorderSide(color: onSurface),
    ),
  );
}

@immutable
class AppearanceTokens extends ThemeExtension<AppearanceTokens> {
  final double blurSigma;

  const AppearanceTokens({required this.blurSigma});

  @override
  AppearanceTokens copyWith({double? blurSigma}) =>
      AppearanceTokens(blurSigma: blurSigma ?? this.blurSigma);

  @override
  AppearanceTokens lerp(ThemeExtension<AppearanceTokens>? other, double t) {
    if (other is! AppearanceTokens) return this;
    return AppearanceTokens(
      blurSigma: blurSigma + (other.blurSigma - blurSigma) * t,
    );
  }
}

extension AppearanceTokensContext on BuildContext {
  AppearanceTokens get appearanceTokens =>
      Theme.of(this).extension<AppearanceTokens>() ??
      const AppearanceTokens(blurSigma: Brand.glassBlurSigma);
}
