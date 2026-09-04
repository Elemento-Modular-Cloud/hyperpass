import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../brand.dart';
import '../catalogue/catalogue.dart';
import '../catalogue/catalogue_surface.dart';
import '../l10n/app_localizations.dart';
import '../llm/catalogue/llm_catalogue_screen.dart';
import '../llm/instances/llm_instances_screen.dart';
import '../llm/providers.dart';
import '../providers.dart';
import '../services/service_branding.dart';
import '../services/service_instance_id.dart';
import '../services/service_instances_screen.dart';
import '../services/service_library.dart';
import '../services/service_status.dart';
import '../services/services_screen.dart';
import '../sidebar.dart';
import '../vm_details/cpu_sparkline.dart';
import '../vm_details/vm_status_icon.dart';
import '../vm_table/vm_table_headers.dart';
import '../vm_table/vm_table_screen.dart';
import '../widgets/resource_meter.dart';

enum OverviewRunningTab { all, vms, llms, services }

class OverviewRunningGrid extends ConsumerStatefulWidget {
  const OverviewRunningGrid({super.key});

  @override
  ConsumerState<OverviewRunningGrid> createState() =>
      _OverviewRunningGridState();
}

class _OverviewRunningGridState extends ConsumerState<OverviewRunningGrid> {
  OverviewRunningTab _tab = OverviewRunningTab.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final glass = context.glass;
    final runningVms = ref
        .watch(vmInfosProvider)
        .where((info) => info.instanceStatus.status == Status.RUNNING)
        .toList();
    final runningServices = ref
        .watch(serviceInstanceInfosProvider)
        .where((info) => info.instanceStatus.status == Status.RUNNING)
        .toList();
    final llmModels = ref.watch(loadedModelsProvider).asData?.value.models ??
        const [];
    final library = ref.watch(marketplaceLibraryProvider).asData?.value;

    final showVms =
        _tab == OverviewRunningTab.all || _tab == OverviewRunningTab.vms;
    final showLlms =
        _tab == OverviewRunningTab.all || _tab == OverviewRunningTab.llms;
    final showServices =
        _tab == OverviewRunningTab.all || _tab == OverviewRunningTab.services;

    final hasAny = (showVms && runningVms.isNotEmpty) ||
        (showLlms && llmModels.isNotEmpty) ||
        (showServices && runningServices.isNotEmpty);

    return CatalogueSurface(
      baseColor: glass.cardSolid.withValues(alpha: 0.6),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.overviewRunningTitle,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  final key = switch (_tab) {
                    OverviewRunningTab.llms => LlmInstancesScreen.sidebarKey,
                    OverviewRunningTab.services =>
                      ServiceInstancesScreen.sidebarKey,
                    OverviewRunningTab.vms ||
                    OverviewRunningTab.all =>
                      VmTableScreen.sidebarKey,
                  };
                  ref.read(sidebarKeyProvider.notifier).set(key);
                },
                child: Text(l10n.overviewRunningViewAll),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tab in OverviewRunningTab.values) ...[
                  if (tab != OverviewRunningTab.all) const SizedBox(width: 4),
                  _TabChip(
                    label: switch (tab) {
                      OverviewRunningTab.all => l10n.overviewRunningTabAll,
                      OverviewRunningTab.vms => l10n.overviewRunningTabVms,
                      OverviewRunningTab.llms => l10n.overviewRunningTabLlms,
                      OverviewRunningTab.services =>
                        l10n.overviewRunningTabServices,
                    },
                    selected: _tab == tab,
                    onTap: () => setState(() => _tab = tab),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (!hasAny)
            _EmptyRunning(tab: _tab)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const minWidth = 280.0;
                const spacing = 16.0;
                final n = max(1, constraints.maxWidth ~/ minWidth);
                final width =
                    (constraints.maxWidth - spacing * (n - 1)) / n;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    if (showVms)
                      for (final vm in runningVms)
                        SizedBox(
                          width: width,
                          child: _VmCard(vm: vm),
                        ),
                    if (showLlms)
                      for (final model in llmModels)
                        SizedBox(
                          width: width,
                          child: _LlmCard(model: model),
                        ),
                    if (showServices)
                      for (final service in runningServices)
                        SizedBox(
                          width: width,
                          child: _ServiceCard(
                            service: service,
                            displayName: library
                                    ?.byId(service.info.serviceId)
                                    ?.displayName ??
                                service.info.serviceId,
                          ),
                        ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _VmCard extends ConsumerWidget {
  const _VmCard({required this.vm});

  final TaggedVmInfo vm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cpuQueue = ref.watch(cpuUsagesProvider(vm.id));
    final cpu = cpuQueue.isEmpty ? 0.0 : cpuQueue.last;
    final memUsed = vm.instanceInfo.memoryUsage;
    final ip = vm.instanceInfo.ipv4.isEmpty ? '—' : vm.instanceInfo.ipv4.first;

    return _WorkloadCard(
      onTap: () =>
          ref.read(sidebarKeyProvider.notifier).set(vm.id.sidebarKey),
      leading: DistroLogo(
        vm.instanceInfo.os,
        release: vm.instanceInfo.currentRelease,
        size: 28,
      ),
      title: vm.name,
      meta: Text(
        'VM · ${l10n.overviewRunningStateRunning}',
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          fontSize: 12,
          color: onSurface.withValues(alpha: 0.65),
        ),
      ),
      lines: [
        'CPU ${cpu.round()}% · RAM ${_shortMem(memUsed)}',
        ip,
      ],
      trailing: VmStatusIcon(vm.instanceStatus.status, isLaunching: false),
    );
  }
}

class _LlmCard extends ConsumerWidget {
  const _LlmCard({required this.model});

  final LoadedModelInfo model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final mem = formatResourceBytes('${model.memoryClaimed}');
    final name = model.modelId.isNotEmpty ? model.modelId : model.instanceId;

    return _WorkloadCard(
      onTap: () => ref.read(sidebarKeyProvider.notifier).set(
            'llm-${Uri.encodeComponent(model.instanceId)}',
          ),
      leading: const FaIcon(
        FontAwesomeIcons.microchip,
        size: 18,
        color: Brand.accent,
      ),
      title: name,
      titleMaxLines: 2,
      meta: Text(
        'LLM · ${l10n.overviewRunningStateRunning}',
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          fontSize: 12,
          color: onSurface.withValues(alpha: 0.65),
        ),
      ),
      lines: [
        model.backend.isNotEmpty ? model.backend : '—',
        mem,
      ],
      trailing: const Icon(Icons.circle, size: 10, color: Brand.accent),
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  const _ServiceCard({required this.service, required this.displayName});

  final TaggedVmInfo service;
  final String displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final status = ref.watch(serviceGuestStatusProvider(service.name));
    final health = status.asData?.value.health ?? ServiceHealthState.unknown;
    final endpoints = status.asData?.value.info?.endpoints ?? const {};
    final endpoint = endpoints.isEmpty
        ? (service.instanceInfo.ipv4.isEmpty
            ? '—'
            : service.instanceInfo.ipv4.first)
        : endpoints.values.first;
    final healthLabel = switch (health) {
      ServiceHealthState.healthy => l10n.overviewRunningHealthHealthy,
      ServiceHealthState.unhealthy => l10n.overviewRunningHealthUnhealthy,
      ServiceHealthState.unreachable => l10n.overviewRunningHealthUnreachable,
      ServiceHealthState.unknown => l10n.overviewRunningHealthUnknown,
    };
    final healthColor = switch (health) {
      ServiceHealthState.healthy => Brand.green,
      ServiceHealthState.unhealthy => const Color(0xFFE35D6A),
      ServiceHealthState.unreachable => Brand.accentDark,
      ServiceHealthState.unknown => onSurface.withValues(alpha: 0.45),
    };
    final openDetails = () {
      ref
          .read(sidebarKeyProvider.notifier)
          .set(serviceInstanceSidebarKey(service.name));
    };
    final unhealthy = health == ServiceHealthState.unhealthy ||
        health == ServiceHealthState.unreachable;

    return _WorkloadCard(
      onTap: openDetails,
      leading: ServiceIconBadge(
        branding: serviceBranding(service.info.serviceId),
        size: 28,
      ),
      title: service.name,
      meta: Text(
        displayName.isNotEmpty ? displayName : 'Service',
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          fontSize: 12,
          color: onSurface.withValues(alpha: 0.65),
        ),
      ),
      lines: [endpoint],
      trailing: _HealthStatus(
        label: healthLabel,
        color: healthColor,
        emphasize: unhealthy,
        onTap: unhealthy ? openDetails : null,
      ),
    );
  }
}

class _HealthStatus extends StatelessWidget {
  const _HealthStatus({
    required this.label,
    required this.color,
    required this.emphasize,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool emphasize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: emphasize
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : EdgeInsets.zero,
      decoration: emphasize
          ? BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 11,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }
}

class _WorkloadCard extends StatelessWidget {
  const _WorkloadCard({
    required this.onTap,
    required this.leading,
    required this.title,
    required this.meta,
    required this.lines,
    required this.trailing,
    this.titleMaxLines = 1,
  });

  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final int titleMaxLines;
  final Widget meta;
  final List<String> lines;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            border: Border.all(color: onSurface.withValues(alpha: 0.12)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(child: leading),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: titleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: Brand.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        meta,
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing,
                ],
              ),
              const SizedBox(height: 14),
              for (final line in lines) ...[
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 12,
                    color: onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 3),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Brand.accent
                    : onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2,
              width: selected ? 28 : 0,
              color: Brand.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRunning extends ConsumerWidget {
  const _EmptyRunning({required this.tab});

  final OverviewRunningTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Text(
            l10n.overviewRunningEmptyTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.overviewRunningEmptyBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              color: onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => ref
                    .read(sidebarKeyProvider.notifier)
                    .set(CatalogueScreen.sidebarKey),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.overviewHeroNewVm),
              ),
              OutlinedButton(
                onPressed: () => ref
                    .read(sidebarKeyProvider.notifier)
                    .set(LlmCatalogueScreen.sidebarKey),
                child: Text(l10n.overviewHeroRunModel),
              ),
              OutlinedButton(
                onPressed: () => ref
                    .read(sidebarKeyProvider.notifier)
                    .set(ServicesScreen.sidebarKey),
                child: Text(l10n.overviewHeroStartService),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _shortMem(String raw) {
  final parsed = int.tryParse(raw);
  if (parsed != null) return formatResourceBytes('$parsed');
  if (raw.isEmpty) return '—';
  return raw;
}
