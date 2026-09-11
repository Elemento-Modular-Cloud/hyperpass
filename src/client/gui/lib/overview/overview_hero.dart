import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../appearance_settings.dart';
import '../auth/feature_access.dart';
import '../brand.dart';
import '../catalogue/catalogue.dart';
import '../l10n/app_localizations.dart';
import '../llm/catalogue/llm_catalogue_screen.dart';
import '../llm/instances/llm_instances_screen.dart';
import '../llm/providers.dart';
import '../providers.dart';
import '../services/service_instances_screen.dart';
import '../services/services_screen.dart';
import '../sidebar.dart';
import '../vm_table/vm_table_screen.dart';
import '../widgets/launchpad_button.dart';

class OverviewHero extends ConsumerWidget {
  const OverviewHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final glass = context.glass;
    final settings = ref.watch(appearanceSettingsProvider);

    final runningVms = ref.watch(vmInfosProvider).where(
          (info) => info.instanceStatus.status == Status.RUNNING,
        ).length;
    final runningServices = ref.watch(serviceInstanceInfosProvider).where(
          (info) => info.instanceStatus.status == Status.RUNNING,
        ).length;
    final runningLlms = ref.watch(loadedLlmIdsProvider).length;
    final total = runningVms + runningServices + runningLlms;
    final healthy = ref.watch(daemonAvailableProvider);
    final access = ref.watch(featureAccessProvider);

    return ClipRRect(
      borderRadius: BorderRadius.circular(Brand.radius + 2),
      child: Stack(
        children: [
          Positioned.fill(child: _HeroBackdrop(settings: settings)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Brand.voidBlack.withValues(alpha: 0.78),
                    Brand.voidBlack.withValues(alpha: 0.45),
                    Brand.voidBlack.withValues(alpha: 0.25),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontFamily: Brand.fontFamily,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                                color: onSurface,
                              ),
                              children: [
                                TextSpan(text: l10n.overviewHeroTitleLead),
                                TextSpan(
                                  text: l10n.overviewHeroTitleAccent,
                                  style: const TextStyle(color: Brand.accent),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Text(
                              l10n.overviewHeroSubtitle,
                              style: TextStyle(
                                fontFamily: Brand.fontFamily,
                                fontSize: 14,
                                height: 1.45,
                                color: onSurface.withValues(alpha: 0.78),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              LaunchPadButton.primary(
                                onPressed: () => ref
                                    .read(sidebarKeyProvider.notifier)
                                    .set(CatalogueScreen.sidebarKey),
                                icon: Icons.add,
                                child: Text(l10n.overviewHeroNewVm),
                              ),
                              Opacity(
                                opacity: access.canUseLlms ? 1 : 0.45,
                                child: AbsorbPointer(
                                  absorbing: !access.canUseLlms,
                                  child: OutlinedButton(
                                    onPressed: () => ref
                                        .read(sidebarKeyProvider.notifier)
                                        .set(LlmCatalogueScreen.sidebarKey),
                                    child: Text(l10n.overviewHeroRunModel),
                                  ),
                                ),
                              ),
                              Opacity(
                                opacity: access.canUseServices ? 1 : 0.45,
                                child: AbsorbPointer(
                                  absorbing: !access.canUseServices,
                                  child: OutlinedButton(
                                    onPressed: () => ref
                                        .read(sidebarKeyProvider.notifier)
                                        .set(ServicesScreen.sidebarKey),
                                    child: Text(l10n.overviewHeroStartService),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    _LocalWorkloadsCard(
                      total: total,
                      vms: runningVms,
                      llms: runningLlms,
                      services: runningServices,
                      healthy: healthy,
                      baseColor: glass.cardSolid,
                      onOpenAll: () {},
                      onOpenVms: () => ref
                          .read(sidebarKeyProvider.notifier)
                          .set(VmTableScreen.sidebarKey),
                      onOpenLlms: access.canUseLlms
                          ? () => ref
                              .read(sidebarKeyProvider.notifier)
                              .set(LlmInstancesScreen.sidebarKey)
                          : () {},
                      onOpenServices: access.canUseServices
                          ? () => ref
                              .read(sidebarKeyProvider.notifier)
                              .set(ServiceInstancesScreen.sidebarKey)
                          : () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalWorkloadsCard extends StatelessWidget {
  const _LocalWorkloadsCard({
    required this.total,
    required this.vms,
    required this.llms,
    required this.services,
    required this.healthy,
    required this.baseColor,
    required this.onOpenAll,
    required this.onOpenVms,
    required this.onOpenLlms,
    required this.onOpenServices,
  });

  final int total;
  final int vms;
  final int llms;
  final int services;
  final bool healthy;
  final Color baseColor;
  final VoidCallback onOpenAll;
  final VoidCallback onOpenVms;
  final VoidCallback onOpenLlms;
  final VoidCallback onOpenServices;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Material(
      color: context.glass.panelUnderlay ?? baseColor,
      borderRadius: BorderRadius.circular(Brand.radius),
      child: InkWell(
        onTap: onOpenAll,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Container(
          width: 260,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            border: Border.all(color: onSurface.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.overviewLocalWorkloadsTitle,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.overviewLocalWorkloadsCount(total),
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Chip(
                    label: l10n.overviewLocalWorkloadsVms(vms),
                    onTap: onOpenVms,
                  ),
                  _Chip(
                    label: l10n.overviewLocalWorkloadsLlms(llms),
                    onTap: onOpenLlms,
                  ),
                  _Chip(
                    label: l10n.overviewLocalWorkloadsServices(services),
                    onTap: onOpenServices,
                  ),
                ],
              ),
              if (healthy) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 8, color: Brand.green),
                    const SizedBox(width: 6),
                    Text(
                      l10n.overviewStatusHealthy,
                      style: TextStyle(
                        fontFamily: Brand.fontFamily,
                        fontSize: 12,
                        color: Brand.green,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: onSurface.withValues(alpha: 0.15)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 11,
            color: onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

class _HeroBackdrop extends ConsumerWidget {
  const _HeroBackdrop({required this.settings});

  final AppearanceSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = ColoredBox(color: themeBackgroundColor(settings.theme));
    final file = wallpaperImageFile(settings);
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    if (settings.wallpaperType == WallpaperType.provider) {
      final url = ref.watch(providerWallpaperUrlProvider).asData?.value;
      if (url != null && url.isNotEmpty) {
        return Image.network(
          url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
        );
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Brand.blackLight,
            Brand.voidBlack,
            Brand.accent.withValues(alpha: 0.25),
          ],
        ),
      ),
    );
  }
}
