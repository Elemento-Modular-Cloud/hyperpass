import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../auth/feature_access.dart';
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
    final access = ref.watch(featureAccessProvider);

    final banners = [
      (
        icon: FontAwesomeIcons.rocket,
        title: l10n.overviewActionCreateTitle,
        body: l10n.overviewActionCreateBody,
        locked: false,
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
        locked: !access.canUseLlms,
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
        locked: !access.canUseServices,
        onOpen: () => ref
            .read(sidebarKeyProvider.notifier)
            .set(ServicesScreen.sidebarKey),
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
              locked: banner.locked,
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
    required this.locked,
    required this.onOpen,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool locked;
  final VoidCallback onOpen;
  final List<({String label, VoidCallback onTap})> actions;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final card = CatalogueSurface(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Brand.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Brand.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Center(
                  child: FaIcon(icon, size: 22, color: Brand.accent),
                ),
              ),
              const Spacer(),
              if (locked)
                Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: onSurface.withValues(alpha: 0.55),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 13,
              height: 1.35,
              color: onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in actions)
                TextButton(
                  onPressed: locked ? null : action.onTap,
                  child: Text(action.label),
                ),
            ],
          ),
        ],
      ),
    );

    return Opacity(
      opacity: locked ? 0.48 : 1,
      child: AbsorbPointer(
        absorbing: locked,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: locked ? null : onOpen,
            borderRadius: BorderRadius.circular(Brand.radius),
            child: card,
          ),
        ),
      ),
    );
  }
}
