import 'package:flutter/material.dart';

class DistroBranding {
  final String logoAsset;
  final String displayName;
  final Color? logoBackground;
  final Color? logoTint;

  const DistroBranding({
    required this.logoAsset,
    required this.displayName,
    this.logoBackground,
    this.logoTint,
  });
}

const _ubuntu = DistroBranding(
  logoAsset: 'assets/ubuntu.svg',
  displayName: 'Ubuntu',
  logoBackground: Color(0xffE95420),
  logoTint: Colors.white,
);

const _debian = DistroBranding(
  logoAsset: 'assets/debian.svg',
  displayName: 'Debian',
);

const _fedora = DistroBranding(
  logoAsset: 'assets/fedora.svg',
  displayName: 'Fedora',
);

const _almalinux = DistroBranding(
  logoAsset: 'assets/almalinux.svg',
  displayName: 'AlmaLinux',
);

const _rocky = DistroBranding(
  logoAsset: 'assets/rocky.svg',
  displayName: 'Rocky Linux',
);

DistroBranding distroBranding(String os) {
  final key = os.toLowerCase();
  if (key.contains('debian')) return _debian;
  if (key.contains('fedora')) return _fedora;
  if (key.contains('almalinux') || key.contains('alma')) return _almalinux;
  if (key.contains('rocky')) return _rocky;
  if (key.contains('ubuntu')) return _ubuntu;
  return _ubuntu;
}

String distroLogoAsset(String os) => distroBranding(os).logoAsset;

String distroDisplayName(String os) {
  if (os.trim().isEmpty) return '-';
  return distroBranding(os).displayName;
}
