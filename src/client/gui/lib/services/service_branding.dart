import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';
import 'service_library.dart';

/// Icon and accent colour for a marketplace service.
///
/// Official catalog artwork comes from `metadata.icon.svg` (a bundled
/// `icon.svg`). `metadata.color` themes the icon badge only. The Font
/// Awesome name is the fallback when the SVG is missing; unknown tools
/// still use a family map, then a cube.
class ServiceBranding {
  const ServiceBranding({required this.icon, required this.accent, this.svg});

  final IconData icon;
  final Color accent;
  final String? svg;
}

const _fallback = ServiceBranding(
  icon: FontAwesomeIcons.cube,
  accent: Brand.accent,
);

/// Keyed by the manifest name with any `_v<N>` suffix removed, so new versions
/// of a service inherit its accent (and a FA icon if the catalog has none).
const _brandingByFamily = <String, ServiceBranding>{
  'caddy_ca': ServiceBranding(
    icon: FontAwesomeIcons.certificate,
    accent: Color(0xFF00B3B6),
  ),
  'hermes': ServiceBranding(
    icon: FontAwesomeIcons.staffSnake,
    accent: Color(0xFFE8A317),
  ),
  'litellm': ServiceBranding(
    icon: FontAwesomeIcons.train,
    accent: Color(0xFF38BDF8),
  ),
  'llmstudio': ServiceBranding(
    icon: FontAwesomeIcons.layerGroup,
    accent: Color(0xFF8B5CF6),
  ),
  'mariadb': ServiceBranding(
    icon: FontAwesomeIcons.database,
    accent: Color(0xFFC49A6C),
  ),
  'minio': ServiceBranding(
    icon: FontAwesomeIcons.hardDrive,
    accent: Color(0xFFC72E49),
  ),
  'mongodb': ServiceBranding(
    icon: FontAwesomeIcons.leaf,
    accent: Color(0xFF47A248),
  ),
  'n8n': ServiceBranding(
    icon: FontAwesomeIcons.diagramProject,
    accent: Color(0xFFEA4B71),
  ),
  'n8n_runner': ServiceBranding(
    icon: FontAwesomeIcons.diagramProject,
    accent: Color(0xFFEA4B71),
  ),
  'npm': ServiceBranding(
    icon: FontAwesomeIcons.networkWired,
    accent: Color(0xFF009639),
  ),
  'openclaw': ServiceBranding(
    icon: FontAwesomeIcons.shrimp,
    accent: Color(0xFFFF4D4D),
  ),
  'openwebui': ServiceBranding(
    icon: FontAwesomeIcons.droplet,
    accent: Color(0xFF3ECC5F),
  ),
  'postgres': ServiceBranding(
    icon: FontAwesomeIcons.database,
    accent: Color(0xFF4169E1),
  ),
  'qdrant': ServiceBranding(
    icon: FontAwesomeIcons.cube,
    accent: Color(0xFFDC244C),
  ),
  'searxng': ServiceBranding(
    icon: FontAwesomeIcons.magnifyingGlass,
    accent: Color(0xFF3050FF),
  ),
  'valkey': ServiceBranding(
    icon: FontAwesomeIcons.key,
    accent: Color(0xFF123678),
  ),
};

/// Font Awesome 6 free solid names used by elemento-marketplace manifests.
const _fontAwesomeByName = <String, IconData>{
  'bolt': FontAwesomeIcons.bolt,
  'certificate': FontAwesomeIcons.certificate,
  'comments': FontAwesomeIcons.comments,
  'cube': FontAwesomeIcons.cube,
  'cubes': FontAwesomeIcons.cubes,
  'database': FontAwesomeIcons.database,
  'diagram-project': FontAwesomeIcons.diagramProject,
  'droplet': FontAwesomeIcons.droplet,
  'hand': FontAwesomeIcons.hand,
  'hard-drive': FontAwesomeIcons.hardDrive,
  'key': FontAwesomeIcons.key,
  'layer-group': FontAwesomeIcons.layerGroup,
  'leaf': FontAwesomeIcons.leaf,
  'magnifying-glass': FontAwesomeIcons.magnifyingGlass,
  'network-wired': FontAwesomeIcons.networkWired,
  'paper-plane': FontAwesomeIcons.paperPlane,
  'robot': FontAwesomeIcons.robot,
  'route': FontAwesomeIcons.route,
  'shrimp': FontAwesomeIcons.shrimp,
  'staff-snake': FontAwesomeIcons.staffSnake,
  'train': FontAwesomeIcons.train,
};

IconData? fontAwesomeIconForName(String? name) {
  if (name == null || name.isEmpty) return null;
  final key = name.trim().toLowerCase().replaceFirst(RegExp(r'^fa-'), '');
  return _fontAwesomeByName[key];
}

/// Parse a catalog `metadata.color` value (`#RRGGBB` or `RRGGBB`).
Color? parseCatalogColor(String? raw) {
  if (raw == null) return null;
  var hex = raw.trim();
  if (hex.isEmpty) return null;
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((ch) => '$ch$ch').join();
  }
  if (hex.length != 6) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// Glyph colour on a catalog accent fill (icon badge).
Color onCatalogAccent(Color accent) {
  return ThemeData.estimateBrightnessForColor(accent) == Brightness.light
      ? Brand.voidBlack
      : Brand.crystalWhite;
}

ServiceBranding serviceBranding(
  String serviceId, {
  MarketplaceService? service,
}) {
  final family = _brandingByFamily[serviceFamily(serviceId)] ?? _fallback;
  return ServiceBranding(
    icon: fontAwesomeIconForName(service?.icon?.fontAwesome) ?? family.icon,
    accent: parseCatalogColor(service?.color) ?? family.accent,
    svg: service?.iconSvg,
  );
}

/// Rounded-square icon badge, matching the catalogue's `DistroLogoBadge`.
class ServiceIconBadge extends StatelessWidget {
  const ServiceIconBadge({
    required this.branding,
    this.size = 40,
    this.semanticsLabel,
    super.key,
  });

  final ServiceBranding branding;
  final double size;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final svg = branding.svg;
    final hasSvg = svg != null && svg.contains('<svg');
    final glyph = onCatalogAccent(branding.accent);

    return Semantics(
      label: semanticsLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: branding.accent,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        padding: EdgeInsets.all(size * 0.18),
        child: hasSvg
            ? SvgPicture.string(
                svg,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(glyph, BlendMode.srcIn),
                excludeFromSemantics: true,
              )
            : Center(
                child: FaIcon(
                  branding.icon,
                  size: size * 0.48,
                  color: glyph,
                ),
              ),
      ),
    );
  }
}
