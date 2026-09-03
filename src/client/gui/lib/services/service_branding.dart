import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';
import 'service_library.dart';

/// Icon and accent colour for a marketplace service.
///
/// The `service.yaml` manifests carry no branding, so tools are matched by
/// name here. Anything unrecognised falls back to a neutral cube.
class ServiceBranding {
  const ServiceBranding({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;
}

const _fallback = ServiceBranding(
  icon: FontAwesomeIcons.cube,
  accent: Brand.accent,
);

/// Keyed by the manifest name with any `_v<N>` suffix removed, so new versions
/// of a service inherit its branding.
const _brandingByFamily = <String, ServiceBranding>{
  'caddy_ca': ServiceBranding(
    icon: FontAwesomeIcons.shieldHalved,
    accent: Color(0xFF1F9C8B),
  ),
  'hermes': ServiceBranding(
    icon: FontAwesomeIcons.robot,
    accent: Color(0xFF8E6FE0),
  ),
  'litellm': ServiceBranding(
    icon: FontAwesomeIcons.shuffle,
    accent: Color(0xFF3FA9F5),
  ),
  'llmstudio': ServiceBranding(
    icon: FontAwesomeIcons.microchip,
    accent: Color(0xFF6C7BE0),
  ),
  'mariadb': ServiceBranding(
    icon: FontAwesomeIcons.database,
    accent: Color(0xFF9C6644),
  ),
  'minio': ServiceBranding(
    icon: FontAwesomeIcons.hardDrive,
    accent: Color(0xFFE0483E),
  ),
  'mongodb': ServiceBranding(
    icon: FontAwesomeIcons.leaf,
    accent: Color(0xFF4DA14B),
  ),
  'n8n': ServiceBranding(
    icon: FontAwesomeIcons.diagramProject,
    accent: Color(0xFFE0567A),
  ),
  'n8n_runner': ServiceBranding(
    icon: FontAwesomeIcons.gears,
    accent: Color(0xFFC7476B),
  ),
  'npm': ServiceBranding(
    icon: FontAwesomeIcons.arrowRightArrowLeft,
    accent: Color(0xFF2E9E5B),
  ),
  'openclaw': ServiceBranding(
    icon: FontAwesomeIcons.paw,
    accent: Color(0xFFD98324),
  ),
  'openwebui': ServiceBranding(
    icon: FontAwesomeIcons.comments,
    accent: Color(0xFF4C8DF6),
  ),
  'postgres': ServiceBranding(
    icon: FontAwesomeIcons.database,
    accent: Color(0xFF31648C),
  ),
  'qdrant': ServiceBranding(
    icon: FontAwesomeIcons.circleNodes,
    accent: Color(0xFFB03A8E),
  ),
  'searxng': ServiceBranding(
    icon: FontAwesomeIcons.magnifyingGlass,
    accent: Color(0xFF3D5AFE),
  ),
  'valkey': ServiceBranding(
    icon: FontAwesomeIcons.bolt,
    accent: Color(0xFFD64545),
  ),
};

ServiceBranding serviceBranding(String serviceId) =>
    _brandingByFamily[serviceFamily(serviceId)] ?? _fallback;

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
    return Semantics(
      label: semanticsLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: branding.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(
            color: branding.accent.withValues(alpha: 0.4),
          ),
        ),
        child: Center(
          child: FaIcon(
            branding.icon,
            size: size * 0.45,
            color: branding.accent,
          ),
        ),
      ),
    );
  }
}
