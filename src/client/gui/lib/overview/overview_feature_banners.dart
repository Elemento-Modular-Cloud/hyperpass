import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';
import '../catalogue/catalogue.dart';
import '../catalogue/catalogue_surface.dart';
import '../l10n/app_localizations.dart';
import '../llm/catalogue/llm_catalogue_screen.dart';
import '../llm/instances/llm_downloaded_screen.dart';
import '../services/service_instances_screen.dart';
import '../services/services_screen.dart';
import '../sidebar.dart';

class OverviewFeatureBanners extends ConsumerWidget {
  const OverviewFeatureBanners({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    final banners = [
      (
        icon: FontAwesomeIcons.rocket,
        title: l10n.overviewActionCreateTitle,
        body: l10n.overviewActionCreateBody,
        onOpen: () => ref
            .read(sidebarKeyProvider.notifier)
            .set(CatalogueScreen.sidebarKey),
        actions: [
          (
            label: l10n.overviewActionLaunchVm,
            onTap: () => ref
                .read(sidebarKeyProvider.notifier)
                .set(CatalogueScreen.sidebarKey),
          ),
          (
            label: l10n.overviewActionImportImage,
            onTap: () => ref
                .read(sidebarKeyProvider.notifier)
                .set(CatalogueScreen.sidebarKey),
          ),
        ],
      ),
      (
        icon: FontAwesomeIcons.wandMagicSparkles,
        title: l10n.overviewActionAiTitle,
        body: l10n.overviewActionAiBody,
        onOpen: () => ref
            .read(sidebarKeyProvider.notifier)
            .set(LlmCatalogueScreen.sidebarKey),
        actions: [
          (
            label: l10n.overviewActionBrowseModels,
            onTap: () => ref
                .read(sidebarKeyProvider.notifier)
                .set(LlmCatalogueScreen.sidebarKey),
          ),
          (
            label: l10n.overviewActionLoadDownloaded,
            onTap: () => ref
                .read(sidebarKeyProvider.notifier)
                .set(LlmDownloadedScreen.sidebarKey),
          ),
        ],
      ),
      (
        icon: FontAwesomeIcons.cubes,
        title: l10n.overviewActionServicesTitle,
        body: l10n.overviewActionServicesBody,
        onOpen: () =>
            ref.read(sidebarKeyProvider.notifier).set(ServicesScreen.sidebarKey),
        actions: [
          (
            label: l10n.overviewActionBrowseServices,
            onTap: () => ref
                .read(sidebarKeyProvider.notifier)
                .set(ServicesScreen.sidebarKey),
          ),
          (
            label: l10n.overviewActionViewDeployments,
            onTap: () => ref
                .read(sidebarKeyProvider.notifier)
                .set(ServiceInstancesScreen.sidebarKey),
          ),
        ],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final children = [
          for (final banner in banners)
            _ActionCard(
              icon: banner.icon,
              title: banner.title,
              body: banner.body,
              onOpen: banner.onOpen,
              actions: banner.actions,
            ),
        ];

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: children[i]),
              ],
            ],
          );
        }

        return Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onOpen,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onOpen;
  final List<({String label, VoidCallback onTap})> actions;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final glass = context.glass;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: CatalogueSurface(
          baseColor: glass.cardSolid.withValues(alpha: 0.6),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FaIcon(icon, size: 16, color: Brand.accent),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 12,
                  height: 1.4,
                  color: onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 14),
              for (final action in actions) ...[
                InkWell(
                  onTap: action.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      action.label,
                      style: const TextStyle(
                        fontFamily: Brand.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Brand.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
