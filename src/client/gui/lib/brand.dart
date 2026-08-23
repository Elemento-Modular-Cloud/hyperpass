import 'package:flutter/material.dart';

/// AtomOS Workstation brand identity (Elemento-powered).
abstract final class Brand {
  static const appName = 'AtomOS Workstation';
  static const companyName = 'Elemento';
  static const logoAsset = 'assets/atomos.svg';
  static const elementoLogoAsset = 'assets/elemento.svg';
  static final docsUrl = Uri.parse('https://www.elemento.cloud');
  static final installUrl = Uri.parse('https://www.elemento.cloud');

  /// AtomOS brand accent.
  static const accent = Color(0xFF118ACB);

  /// Light tint for active sidebar rows on light theme.
  static const accentLight = Color(0xFFD6EBF7);

  /// Darker accent for hover / pressed CTAs.
  static const accentDark = Color(0xFF0E6FA3);

  /// Elemento Starter Yellow — footer chrome only.
  static const yellow = Color(0xFFFFA600);

  /// Status / online indicator (Electros `--green`).
  static const green = Color(0xFF28A745);

  /// Lighter yellow (Elemento footer hover).
  static const yellowLight = Color(0xFFFAB83A);

  /// Darker yellow for Elemento footer hover.
  static const yellowDark = Color(0xFFF28E00);

  /// Void Black — primary dark field (sidebar).
  static const voidBlack = Color(0xFF16161D);

  /// Electros dark page background (`--black`).
  static const black = Color(0xFF1A1C20);

  /// Electros dark elevated surface (`--black-light`).
  static const blackLight = Color(0xFF2F3338);

  /// Crystal White — text / logo on dark.
  static const crystalWhite = Color(0xFFF8F8FF);

  /// Light page background (`--white`).
  static const white = Color(0xFFF5F5FA);

  /// Pure white surfaces.
  static const whiteLight = Color(0xFFFFFFFF);

  /// Secondary text on dark chrome (`--grey-light`).
  static const greyBody = Color(0xFFB0B5BA);

  /// Body text on light surfaces (`--grey-darker`).
  static const greyDarker = Color(0xFF4A4E53);

  /// Corner radius used for buttons, cards, and inputs.
  static const radius = 6.0;

  /// Backdrop blur sigma matching Electros `--backdrop-blur: blur(10px)`.
  static const glassBlurSigma = 10.0;

  static const fontFamily = 'RedHatDisplay';
}

/// Hidden render-time boost so Flutter matches Electron/CSS compositing.
///
/// Stored appearance values stay Electros-compatible; only alpha at paint time
/// is adjusted.
const double kFlutterOpacityCompensationPercent = 5;

double renderOpacityAlpha(double storedOpacityPercent) {
  return ((storedOpacityPercent + kFlutterOpacityCompensationPercent) / 100)
      .clamp(0.0, 1.0);
}

Color boostRenderAlpha(Color color) {
  if (color.a >= 1) return color;
  return color.withValues(
    alpha: (color.a + kFlutterOpacityCompensationPercent / 100).clamp(0, 1),
  );
}

/// Theme-dependent glass / surface tokens (ElectrosGUI glassmorphism recipe).
@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  final Color fill;
  final Color border;
  final Color gradientStart;
  final Color gradientMid;
  final List<BoxShadow> shadows;
  final Color cardSolid;

  const GlassTokens({
    required this.fill,
    required this.border,
    required this.gradientStart,
    required this.gradientMid,
    required this.shadows,
    required this.cardSolid,
  });

  static const light = GlassTokens(
    fill: Color(0x47FFFFFF), // rgba(255,255,255,0.28)
    border: Color(0x40C8C8C8), // rgba(200,200,200,0.25)
    gradientStart: Color(0x59FFFFFF),
    gradientMid: Color(0x2EDCDCDC),
    shadows: [
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
      BoxShadow(
        color: Color(0x33FFFFFF),
        blurRadius: 0,
        offset: Offset(0, 1),
        blurStyle: BlurStyle.inner,
      ),
    ],
    cardSolid: Brand.whiteLight,
  );

  static const dark = GlassTokens(
    fill: Color(0x14505050), // rgba(80,80,80,0.08)
    border: Color(0x14787878), // rgba(120,120,120,0.08)
    gradientStart: Color(0x26FFFFFF),
    gradientMid: Color(0x14787878),
    shadows: [
      BoxShadow(
        color: Color(0x29000000),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
      BoxShadow(
        color: Color(0x14FFFFFF),
        blurRadius: 0,
        offset: Offset(0, 1),
        blurStyle: BlurStyle.inner,
      ),
    ],
    cardSolid: Brand.black,
  );

  static const highContrast = GlassTokens(
    fill: Color(0x33282828), // rgba(40,40,40,0.20)
    border: Color(0x4D505050), // rgba(80,80,80,0.30)
    gradientStart: Color(0x40282828),
    gradientMid: Color(0x33141414),
    shadows: [
      BoxShadow(
        color: Color(0x33000000),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
      BoxShadow(
        color: Color(0x26282828),
        blurRadius: 0,
        offset: Offset(0, 1),
        blurStyle: BlurStyle.inner,
      ),
    ],
    cardSolid: Colors.black,
  );

  /// Solid card surface when glassmorphism is disabled.
  static GlassTokens solid({
    required Color colour,
    required double opacityPercent,
  }) {
    final alpha = renderOpacityAlpha(opacityPercent);
    final fill = colour.withValues(alpha: alpha);
    return GlassTokens(
      fill: fill,
      border: fill.withValues(alpha: (alpha * 0.5).clamp(0, 1)),
      gradientStart: fill,
      gradientMid: fill,
      shadows: const [],
      cardSolid: fill,
    );
  }

  /// Apply [kFlutterOpacityCompensationPercent] to semi-transparent tokens.
  GlassTokens withRenderOpacityCompensation() {
    return copyWith(
      fill: boostRenderAlpha(fill),
      border: boostRenderAlpha(border),
      gradientStart: boostRenderAlpha(gradientStart),
      gradientMid: boostRenderAlpha(gradientMid),
      cardSolid: cardSolid.a < 1 ? boostRenderAlpha(cardSolid) : cardSolid,
    );
  }

  @override
  GlassTokens copyWith({
    Color? fill,
    Color? border,
    Color? gradientStart,
    Color? gradientMid,
    List<BoxShadow>? shadows,
    Color? cardSolid,
  }) {
    return GlassTokens(
      fill: fill ?? this.fill,
      border: border ?? this.border,
      gradientStart: gradientStart ?? this.gradientStart,
      gradientMid: gradientMid ?? this.gradientMid,
      shadows: shadows ?? this.shadows,
      cardSolid: cardSolid ?? this.cardSolid,
    );
  }

  @override
  GlassTokens lerp(ThemeExtension<GlassTokens>? other, double t) {
    if (other is! GlassTokens) return this;
    return GlassTokens(
      fill: Color.lerp(fill, other.fill, t)!,
      border: Color.lerp(border, other.border, t)!,
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientMid: Color.lerp(gradientMid, other.gradientMid, t)!,
      shadows: t < 0.5 ? shadows : other.shadows,
      cardSolid: Color.lerp(cardSolid, other.cardSolid, t)!,
    );
  }
}

extension GlassTokensContext on BuildContext {
  GlassTokens get glass {
    return Theme.of(this).extension<GlassTokens>() ?? GlassTokens.light;
  }
}
