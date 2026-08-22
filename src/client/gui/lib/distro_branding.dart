import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

class DistroBranding {
  final String logoAsset;
  final String displayName;
  final Color background;
  final Color accent;
  final Color? logoBackground;
  final Color? logoTint;

  const DistroBranding({
    required this.logoAsset,
    required this.displayName,
    required this.background,
    required this.accent,
    this.logoBackground,
    this.logoTint,
  });

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

const _ubuntu = DistroBranding(
  logoAsset: 'assets/ubuntu.svg',
  displayName: 'Ubuntu',
  background: Color(0xff380c2a),
  accent: Color(0xffE95420),
  logoBackground: Color(0xffE95420),
  logoTint: Colors.white,
);

const _debian = DistroBranding(
  logoAsset: 'assets/debian.svg',
  displayName: 'Debian',
  background: Color(0xff2d0a16),
  accent: Color(0xffd70a53),
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

DistroBranding distroBranding(String os) {
  final key = os.toLowerCase();
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
  if (key.contains('ubuntu')) return _ubuntu;
  return _ubuntu;
}

String distroLogoAsset(String os) => distroBranding(os).logoAsset;

String distroDisplayName(String os) {
  if (os.trim().isEmpty) return '-';
  return distroBranding(os).displayName;
}
