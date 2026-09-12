import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xterm/xterm.dart';

/// Electros LaunchPad brand identity (Elemento-powered).
abstract final class Brand {
  static const appNamePrimary = 'Electros';
  static const appNameSecondary = 'LaunchPad';
  static const appName = '$appNamePrimary $appNameSecondary';
  static const companyName = 'Elemento';
  static const logoAsset = 'assets/atomos.svg';
  static const elementoLogoAsset = 'assets/elemento.svg';
  static final docsUrl = Uri.parse('https://www.elemento.cloud');
  static final installUrl = Uri.parse('https://www.elemento.cloud');

  /// LaunchPad orange sampled from [logoAsset] (`rgb(255,122,0)`).
  static const primary = Color(0xFFFF7A00);

  /// Hover state for primary actions.
  static const primaryHover = Color(0xFFE56E00);

  /// Pressed / active state for primary actions.
  static const primaryActive = Color(0xFFCC6200);

  /// Translucent primary for fills, focus glow, and selected chips.
  static const primaryMuted = Color(0x2EFF7A00);

  /// Alias of [primary] for existing call sites.
  static const accent = primary;

  /// Light tint for active sidebar rows on light theme.
  static const accentLight = Color(0xFFFFCCB3);

  /// Alias of [primaryHover] for existing call sites.
  static const accentDark = primaryHover;

  /// @Deprecated — use [primary]. Kept so footer chrome compiles.
  static const yellow = primary;

  /// Status / online indicator (Electros `--green`).
  static const green = Color(0xFF28A745);

  /// Capacity warning (true yellow — never LaunchPad orange).
  static const warning = Color(0xFFE8C547);

  /// Information / network / normal utilization.
  static const info = Color(0xFF6CB6FF);

  /// Critical utilization and error chrome.
  static const critical = Color(0xFFE35D6A);

  /// Destructive button fill.
  static const destructive = Color(0xFFC7162B);

  /// Fixed palette for host resource split (VMs / AI / services).
  static const workloadVm = Color(0xFF2F9E88);
  static const workloadAi = Color(0xFFC792EA);
  static const workloadService = Color(0xFF7B6CF0);

  /// @Deprecated — use [primaryHover].
  static const yellowLight = primaryHover;

  /// @Deprecated — use [primaryActive].
  static const yellowDark = primaryActive;

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

  /// Dialog barrier over the app chrome.
  static const barrier = Color(0xCC0A0A10);

  /// Shared corner radius for buttons, fields, cards, tables, dialogs, and panels.
  static const radius = 8.0;

  /// Fully rounded ends for chips, avatars, and status pills.
  static const radiusPill = 999.0;

  /// Backdrop blur sigma matching Electros `--backdrop-blur: blur(10px)`.
  static const glassBlurSigma = 10.0;

  static const fontFamily = 'RedHatDisplay';

  /// Terminal / log palette matching Electros LaunchPad (not distro themes).
  static TerminalTheme get terminalTheme => const TerminalTheme(
        cursor: primary,
        selection: Color(0x66FF7A00),
        foreground: crystalWhite,
        background: voidBlack,
        black: Color(0xFF000000),
        red: critical,
        green: green,
        yellow: warning,
        blue: info,
        magenta: Color(0xFFC792EA),
        cyan: Color(0xFF89DDFF),
        white: crystalWhite,
        brightBlack: greyBody,
        brightRed: Color(0xFFFF7B72),
        brightGreen: Color(0xFF3DD68C),
        brightYellow: warning,
        brightBlue: Color(0xFF79C0FF),
        brightMagenta: Color(0xFFD2A8FF),
        brightCyan: Color(0xFFA5F3FC),
        brightWhite: whiteLight,
        searchHitBackground: Color(0xFFFFFF2B),
        searchHitBackgroundCurrent: Color(0xFF31FF26),
        searchHitForeground: Color(0xFF000000),
      );
}

/// Electros mark from [Brand.logoAsset].
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.width,
    this.height,
    this.colorFilter,
  });

  final double? width;
  final double? height;
  final ColorFilter? colorFilter;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      Brand.logoAsset,
      width: width,
      height: height,
      colorFilter: colorFilter,
    );
  }
}

/// Renders [Brand.appName] with a lighter weight on the product suffix.
class BrandAppName extends StatelessWidget {
  const BrandAppName({
    super.key,
    required this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final primaryWeight = style.fontWeight ?? FontWeight.w700;
    final secondaryWeight = switch (primaryWeight) {
      FontWeight.w700 || FontWeight.w800 || FontWeight.w900 => FontWeight.w400,
      FontWeight.w600 => FontWeight.w400,
      _ => FontWeight.w300,
    };

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(
            text: Brand.appNamePrimary,
            style: TextStyle(fontWeight: primaryWeight),
          ),
          TextSpan(
            text: ' ${Brand.appNameSecondary}',
            style: TextStyle(fontWeight: secondaryWeight),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      textAlign: textAlign,
    );
  }
}

/// Hidden render-time boost so Flutter matches Electron/CSS compositing.
///
/// Stored appearance values stay Electros-compatible; only alpha at paint time
/// is adjusted.
const double kFlutterOpacityCompensationPercent = 5;

/// Surface roles with predictable opacity / elevation.
enum SurfaceRole {
  app,
  sidebar,
  card,
  panel,
  elevated,
  modal,
}

/// Shared underlay alpha for atmospheric surfaces (sidebar + catalog cards).
const double kPanelUnderlayAlpha = 0.52;

/// Underlay alpha for functional page surfaces (instances, settings, logs).
const double kFunctionalUnderlayAlpha = 0.86;

/// Underlay alpha for menus and dropdowns.
const double kElevatedUnderlayAlpha = 0.92;

/// Underlay alpha for dialogs.
const double kModalUnderlayAlpha = 0.94;

double underlayAlphaFor(SurfaceRole role) => switch (role) {
      SurfaceRole.app => 0,
      SurfaceRole.sidebar || SurfaceRole.card => kPanelUnderlayAlpha,
      SurfaceRole.panel => kFunctionalUnderlayAlpha,
      SurfaceRole.elevated => kElevatedUnderlayAlpha,
      SurfaceRole.modal => kModalUnderlayAlpha,
    };

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

  /// Underlay shared by sidebar, cards, and pages.
  ///
  /// Glass themes keep an opaque [cardSolid] and need this tint for readability.
  /// Solid (non-glass) mode already encodes opacity in [fill]/[cardSolid], so
  /// no extra underlay is applied.
  Color? get panelUnderlay => underlayFor(SurfaceRole.card);

  Color? underlayFor(SurfaceRole role) {
    if (cardSolid.a < 1.0) return null;
    final alpha = underlayAlphaFor(role);
    if (alpha <= 0) return null;
    return cardSolid.withValues(alpha: alpha);
  }

  Color get modalFill => cardSolid.withValues(alpha: kModalUnderlayAlpha);

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
