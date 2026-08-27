import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xterm/xterm.dart';

import 'brand.dart';

class DistroBranding {
  final String logoAsset;
  final String displayName;
  final Color background;
  final Color accent;
  final Color? logoBackground;
  final Color? logoBackgroundLight;
  final Color? logoTint;
  final Color? logoTintLight;

  const DistroBranding({
    required this.logoAsset,
    required this.displayName,
    required this.background,
    required this.accent,
    this.logoBackground,
    this.logoBackgroundLight,
    this.logoTint,
    this.logoTintLight,
  });

  Color? resolvedLogoBackground(Brightness brightness) {
    if (brightness == Brightness.light) {
      return logoBackgroundLight ?? logoBackground;
    }
    return logoBackground;
  }

  Color? resolvedLogoTint(Brightness brightness) {
    if (brightness == Brightness.light) {
      return logoTintLight ?? logoTint;
    }
    return logoTint;
  }

  TerminalTheme get terminalTheme => TerminalTheme(
        cursor: const Color(0xFFE5E5E5),
        selection: const Color(0x80E5E5E5),
        foreground: const Color(0xffffffff),
        background: background,
        black: const Color(0xFF000000),
        white: const Color(0xFFE5E5E5),
        red: const Color(0xFFCD3131),
        green: const Color(0xFF0DBC79),
        yellow: const Color(0xFFE5E510),
        blue: const Color(0xFF2472C8),
        magenta: const Color(0xFFBC3FBC),
        cyan: const Color(0xFF11A8CD),
        brightBlack: const Color(0xFF666666),
        brightRed: const Color(0xFFF14C4C),
        brightGreen: const Color(0xFF23D18B),
        brightYellow: const Color(0xFFF5F543),
        brightBlue: const Color(0xFF3B8EEA),
        brightMagenta: const Color(0xFFD670D6),
        brightCyan: const Color(0xFF29B8DB),
        brightWhite: const Color(0xFFFFFFFF),
        searchHitBackground: const Color(0XFFFFFF2B),
        searchHitBackgroundCurrent: const Color(0XFF31FF26),
        searchHitForeground: const Color(0XFF000000),
      );
}

const _ubuntuServer = DistroBranding(
  logoAsset: 'assets/ubuntu.svg',
  displayName: 'Ubuntu',
  background: Color(0xff380c2a),
  accent: Color(0xffE95420),
  // Soft plate + orange mark (switched with Core for clearer catalog contrast).
  logoTint: Color(0xffE95420),
);

const _ubuntuCore = DistroBranding(
  logoAsset: 'assets/ubuntu.svg',
  displayName: 'Ubuntu Core',
  background: Color(0xff380c2a),
  accent: Color(0xffE95420),
  logoBackground: Color(0x59E95420),
  logoTint: Colors.white,
);

const _debian = DistroBranding(
  logoAsset: 'assets/debian.svg',
  displayName: 'Debian',
  background: Color(0xff2d0a16),
  accent: Color(0xffd70a53),
  logoTint: Colors.white,
  // Native maroon swirl; white-on-pink is unreadable in light mode.
  logoTintLight: Color(0xffA80030),
);

const _fedora = DistroBranding(
  logoAsset: 'assets/fedora.svg',
  displayName: 'Fedora',
  background: Color(0xff0b1f33),
  accent: Color(0xff3c6eb4),
);

const _almalinux = DistroBranding(
  logoAsset: 'assets/almalinux.svg',
  displayName: 'AlmaLinux',
  background: Color(0xff071a2c),
  accent: Color(0xff0c74c7),
);

const _rocky = DistroBranding(
  logoAsset: 'assets/rocky.svg',
  displayName: 'Rocky Linux',
  background: Color(0xff0a1f14),
  accent: Color(0xff10b981),
);

const _opensuse = DistroBranding(
  logoAsset: 'assets/opensuse.svg',
  displayName: 'openSUSE',
  background: Color(0xff1a2e0a),
  accent: Color(0xff73ba25),
);

const _centos = DistroBranding(
  logoAsset: 'assets/centos.svg',
  displayName: 'CentOS Stream',
  background: Color(0xff1a1520),
  accent: Color(0xff9d2f6c),
);

const _oraclelinux = DistroBranding(
  logoAsset: 'assets/oraclelinux.svg',
  displayName: 'Oracle Linux',
  background: Color(0xff2a1210),
  accent: Color(0xffc74634),
);

const _arch = DistroBranding(
  logoAsset: 'assets/arch.svg',
  displayName: 'Arch Linux',
  background: Color(0xff0b1c28),
  accent: Color(0xff1793d1),
);

const _alpine = DistroBranding(
  logoAsset: 'assets/alpine.svg',
  displayName: 'Alpine Linux',
  background: Color(0xff0a2430),
  accent: Color(0xff0d597f),
  logoBackground: Color(0x660d597f),
  logoBackgroundLight: Color(0x330d597f),
  logoTint: Colors.white,
  logoTintLight: Colors.black,
);

const _amazonlinux = DistroBranding(
  logoAsset: 'assets/amazonlinux.png',
  displayName: 'Amazon Linux',
  background: Color(0xff141c24),
  accent: Color(0xffff9900),
  // Soft white plate so the dark bird stays readable without a hard white square.
  logoBackground: Color(0x40FFFFFF),
);

DistroBranding distroBranding(
  String os, {
  bool isCore = false,
  String? release,
}) {
  // Multipass often leaves `os` blank and puts e.g. "Ubuntu 24.04 LTS" in release.
  final key = '$os ${release ?? ''}'.trim().toLowerCase();
  if (key.isEmpty) return _ubuntuServer;

  if (key.contains('debian')) return _debian;
  if (key.contains('fedora')) return _fedora;
  if (key.contains('almalinux') || key.contains('alma')) return _almalinux;
  if (key.contains('rocky')) return _rocky;
  if (key.contains('opensuse') || key.contains('suse') || key.contains('tumbleweed')) {
    return _opensuse;
  }
  if (key.contains('centos')) return _centos;
  if (key.contains('oracle')) return _oraclelinux;
  if (key.contains('arch')) return _arch;
  if (key.contains('alpine')) return _alpine;
  if (key.contains('amazon')) return _amazonlinux;
  if (key.contains('ubuntu')) {
    final core = isCore || key.contains('core');
    return core ? _ubuntuCore : _ubuntuServer;
  }
  return _ubuntuServer;
}

/// True when [os], [release], or [aliases] indicate an Ubuntu Core image.
bool distroIsCore({
  String os = '',
  String? release,
  Iterable<String>? aliases,
}) {
  final key = os.toLowerCase();
  if (key.contains('core')) return true;
  if (release != null && release.toLowerCase().contains('core')) return true;
  if (aliases != null && aliases.any((a) => a.toLowerCase().contains('core'))) {
    return true;
  }
  return false;
}

String distroLogoAsset(String os, {String? release}) =>
    distroBranding(os, release: release).logoAsset;

String distroDisplayName(String os, {String? release}) {
  if (os.trim().isEmpty && (release == null || release.trim().isEmpty)) {
    return '-';
  }
  return distroBranding(os, release: release).displayName;
}

bool distroLogoIsRaster(String asset) =>
    asset.endsWith('.png') ||
    asset.endsWith('.jpg') ||
    asset.endsWith('.jpeg') ||
    asset.endsWith('.webp');

/// Renders a distro logo from SVG or raster assets.
Widget distroLogoPicture(
  DistroBranding branding, {
  required double size,
  ColorFilter? colorFilter,
  String? semanticsLabel,
}) {
  final asset = branding.logoAsset;
  if (distroLogoIsRaster(asset)) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: semanticsLabel,
    );
  }
  return SvgPicture.asset(
    asset,
    width: size,
    height: size,
    fit: BoxFit.contain,
    colorFilter: colorFilter,
    semanticsLabel: semanticsLabel,
  );
}

/// Rounded-square distro mark used by catalogue cards, cache, and instances.
class DistroLogoBadge extends StatelessWidget {
  const DistroLogoBadge({
    required this.branding,
    required this.size,
    this.semanticsLabel,
    super.key,
  });

  final DistroBranding branding;
  final double size;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isRaster = distroLogoIsRaster(branding.logoAsset);
    final logoTint = branding.resolvedLogoTint(brightness);
    final logoBackground = branding.resolvedLogoBackground(brightness);

    final Color badgeFill;
    if (logoBackground != null) {
      badgeFill = logoBackground;
    } else if (isRaster) {
      badgeFill = Colors.transparent;
    } else {
      badgeFill = branding.accent.withValues(alpha: 0.12);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: badgeFill,
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: branding.accent.withValues(alpha: 0.45)),
      ),
      padding: EdgeInsets.all(isRaster ? size * 0.08 : size * 0.18),
      child: distroLogoPicture(
        branding,
        size: size,
        semanticsLabel: semanticsLabel,
        colorFilter: logoTint == null
            ? null
            : ColorFilter.mode(logoTint, BlendMode.srcIn),
      ),
    );
  }
}
