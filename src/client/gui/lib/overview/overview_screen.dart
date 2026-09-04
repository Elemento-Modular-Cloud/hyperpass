import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';
import '../catalogue/catalogue.dart';
import '../l10n/app_localizations.dart';
import '../llm/catalogue/llm_catalogue_screen.dart';
import '../llm/host_resource_gauges.dart';
import '../llm/instances/llm_downloaded_screen.dart';
import '../llm/instances/llm_instances_screen.dart';
import '../llm/providers.dart';
import '../page_surface.dart';
import '../providers.dart';
import '../services/service_instances_screen.dart';
import '../services/services_screen.dart';
import '../sidebar.dart';
import '../vm_table/vm_table_screen.dart';

class OverviewScreen extends ConsumerWidget {
  static const sidebarKey = 'overview';

  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final vmCount = ref.watch(vmIdsProvider).length;
    final llmCount = ref.watch(loadedLlmIdsProvider).length;
    final serviceCount = ref.watch(serviceInstanceIdsProvider).length;
    final downloaded = ref.watch(loadedModelsProvider).maybeWhen(
          data: (reply) => reply.cached.length,
          orElse: () => 0,
        );

    return Scaffold(
      body: PageSurface(
        child: ListView(
          children: [
            Text(
              l10n.overviewLabel,
              style: const TextStyle(
                fontSize: 37,
                fontWeight: FontWeight.w300,
                fontFamily: Brand.fontFamily,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.overviewSubtitle,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                color: onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            const HostResourceGauges(),
            const SizedBox(height: 28),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _OverviewCard(
                  icon: FontAwesomeIcons.server,
                  title: l10n.sidebarInstances,
                  value: '$vmCount',
                  hint: l10n.overviewVmsHint,
                  onOpen: () => ref
                      .read(sidebarKeyProvider.notifier)
                      .set(VmTableScreen.sidebarKey),
                  onSecondary: () => ref
                      .read(sidebarKeyProvider.notifier)
                      .set(CatalogueScreen.sidebarKey),
                  secondaryLabel: l10n.catalogueLabel,
                ),
                _OverviewCard(
                  icon: FontAwesomeIcons.microchip,
                  title: l10n.llmInstancesLabel,
                  value: '$llmCount',
                  hint: l10n.overviewLlmsHint(downloaded),
                  onOpen: () => ref
                      .read(sidebarKeyProvider.notifier)
                      .set(LlmInstancesScreen.sidebarKey),
                  onSecondary: () => ref
                      .read(sidebarKeyProvider.notifier)
                      .set(LlmCatalogueScreen.sidebarKey),
                  secondaryLabel: l10n.llmCatalogueLabel,
                  onTertiary: () => ref
                      .read(sidebarKeyProvider.notifier)
                      .set(LlmDownloadedScreen.sidebarKey),
                  tertiaryLabel: l10n.llmDownloadedLabel,
                ),
                _OverviewCard(
                  icon: FontAwesomeIcons.cubes,
                  title: l10n.serviceInstancesLabel,
                  value: '$serviceCount',
                  hint: l10n.overviewServicesHint,
                  onOpen: () => ref
                      .read(sidebarKeyProvider.notifier)
                      .set(ServiceInstancesScreen.sidebarKey),
                  onSecondary: () => ref
                      .read(sidebarKeyProvider.notifier)
                      .set(ServicesScreen.sidebarKey),
                  secondaryLabel: l10n.servicesLabel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.hint,
    required this.onOpen,
    required this.onSecondary,
    required this.secondaryLabel,
    this.onTertiary,
    this.tertiaryLabel,
  });

  final IconData icon;
  final String title;
  final String value;
  final String hint;
  final VoidCallback onOpen;
  final VoidCallback onSecondary;
  final String secondaryLabel;
  final VoidCallback? onTertiary;
  final String? tertiaryLabel;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(Brand.radius),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radius),
              border: Border.all(
                color: onSurface.withValues(alpha: 0.15),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FaIcon(icon, size: 16, color: Brand.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontWeight: FontWeight.w600,
                          color: onSurface.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 40,
                    fontWeight: FontWeight.w300,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 13,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: onOpen,
                      child: Text(title),
                    ),
                    OutlinedButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel),
                    ),
                    if (onTertiary != null && tertiaryLabel != null)
                      OutlinedButton(
                        onPressed: onTertiary,
                        child: Text(tertiaryLabel!),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
