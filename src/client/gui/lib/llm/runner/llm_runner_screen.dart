import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../auth/feature_access.dart';
import '../../auth/feature_lock.dart';
import '../../brand.dart';
import '../../catalogue/catalogue_surface.dart';
import '../../l10n/app_localizations.dart';
import '../../page_surface.dart';
import 'llm_accelerator.dart';
import 'llm_runner_providers.dart';

/// Host inference fabric: one card per accelerator, with combining gated.
class LlmRunnerScreen extends ConsumerWidget {
  static const sidebarKey = 'llm-runner';

  const LlmRunnerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final snapshot = ref.watch(llmRunnerSnapshotProvider);
    final selected = ref.watch(llmRunnerSelectedIdsProvider);
    final canCombine = ref.watch(featureAccessProvider).canCombineAccelerators;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageSurface(
        baseColor: context.glass.cardSolid,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.llmRunnerLabel,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 37,
                fontWeight: FontWeight.w300,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.llmRunnerSubtitle,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 13,
                height: 1.4,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 24),
            _BackendStrip(snapshot: snapshot),
            const SizedBox(height: 24),
            Text(
              l10n.llmRunnerAcceleratorsTitle,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final cards = [
                    for (final accelerator in snapshot.accelerators)
                      _AcceleratorCard(
                        accelerator: accelerator,
                        selected: selected.contains(accelerator.id),
                        onTap: accelerator.selectable
                            ? () => _onTapAccelerator(
                                  ref,
                                  accelerator: accelerator,
                                  selected: selected.toSet(),
                                  canCombine: canCombine,
                                )
                            : null,
                      ),
                  ];
                  final combine = _CombinePanel(
                    snapshot: snapshot,
                    selectedIds: selected.toSet(),
                    canCombine: canCombine,
                  );
                  final body = wide
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < cards.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 14),
                                    Expanded(child: cards[i]),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            combine,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              if (i > 0) const SizedBox(height: 12),
                              cards[i],
                            ],
                            const SizedBox(height: 16),
                            combine,
                          ],
                        );
                  return SingleChildScrollView(child: body);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTapAccelerator(
    WidgetRef ref, {
    required LlmAccelerator accelerator,
    required Set<String> selected,
    required bool canCombine,
  }) {
    final next = applyAcceleratorTap(
      selected: selected,
      accelerator: accelerator,
      canCombine: canCombine,
    );
    ref.read(llmRunnerStoredSelectionProvider.notifier).setIds(next);
  }
}

class _BackendStrip extends StatelessWidget {
  const _BackendStrip({required this.snapshot});

  final LlmRunnerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final ready = snapshot.backendReady;
    final color = ready ? Brand.green : Theme.of(context).colorScheme.error;
    return CatalogueSurface(
      baseColor: context.glass.cardSolid,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderColor: color.withValues(alpha: 0.4),
      child: Row(
        children: [
          FaIcon(
            FontAwesomeIcons.server,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.llmRunnerBackendTitle,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  snapshot.backendName,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
                if (snapshot.backendDetail.isNotEmpty)
                  Text(
                    snapshot.backendDetail,
                    style: TextStyle(
                      fontFamily: Brand.fontFamily,
                      fontSize: 12,
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          _StatusPill(
            label: ready
                ? l10n.llmRunnerBackendReady
                : l10n.llmRunnerBackendMissing,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _AcceleratorCard extends StatelessWidget {
  const _AcceleratorCard({
    required this.accelerator,
    required this.selected,
    required this.onTap,
  });

  final LlmAccelerator accelerator;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final kindColor = switch (accelerator.kind) {
      LlmAcceleratorKind.cpu => Brand.workloadVm,
      LlmAcceleratorKind.gpu => Brand.info,
      LlmAcceleratorKind.mpu => Brand.workloadAi,
    };
    final kindLabel = switch (accelerator.kind) {
      LlmAcceleratorKind.cpu => l10n.llmRunnerKindCpu,
      LlmAcceleratorKind.gpu => l10n.llmRunnerKindGpu,
      LlmAcceleratorKind.mpu => l10n.llmRunnerKindMpu,
    };
    final icon = switch (accelerator.kind) {
      LlmAcceleratorKind.cpu => FontAwesomeIcons.microchip,
      LlmAcceleratorKind.gpu => FontAwesomeIcons.display,
      LlmAcceleratorKind.mpu => FontAwesomeIcons.bolt,
    };
    final status = selected
        ? l10n.llmRunnerStatusSelected
        : !accelerator.available
            ? l10n.llmRunnerStatusUnavailable
            : !accelerator.usableByRunner
                ? l10n.llmRunnerStatusNotUsable
                : l10n.llmRunnerStatusAvailable;
    final statusColor = selected
        ? Brand.accent
        : !accelerator.available
            ? onSurface.withValues(alpha: 0.45)
            : !accelerator.usableByRunner
                ? Brand.warning
                : Brand.green;
    final border = selected
        ? Brand.accent
        : onSurface.withValues(alpha: accelerator.available ? 0.16 : 0.1);

    return CatalogueSurface(
      key: Key('llm-accelerator-${accelerator.id}'),
      baseColor: context.glass.cardSolid,
      padding: EdgeInsets.zero,
      borderColor: border,
      borderWidth: selected ? 1.6 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Brand.radius),
          child: Opacity(
            opacity: accelerator.available ? 1 : 0.62,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: kindColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(Brand.radius),
                        ),
                        child: Center(
                          child: FaIcon(icon, size: 16, color: kindColor),
                        ),
                      ),
                      const Spacer(),
                      _StatusPill(label: kindLabel, color: kindColor),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    accelerator.name,
                    style: TextStyle(
                      fontFamily: Brand.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    accelerator.detail,
                    style: TextStyle(
                      fontFamily: Brand.fontFamily,
                      fontSize: 12,
                      height: 1.35,
                      color: onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _StatusPill(label: status, color: statusColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CombinePanel extends ConsumerWidget {
  const _CombinePanel({
    required this.snapshot,
    required this.selectedIds,
    required this.canCombine,
  });

  final LlmRunnerSnapshot snapshot;
  final Set<String> selectedIds;
  final bool canCombine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final names = [
      for (final accelerator in snapshot.accelerators)
        if (selectedIds.contains(accelerator.id)) accelerator.name,
    ];
    final composition = names.isEmpty
        ? l10n.llmRunnerCompositionLocked
        : names.length == 1
            ? l10n.llmRunnerCompositionSingle(names.first)
            : l10n.llmRunnerCompositionCombined(names.join(', '));
    final selectable = allSelectableAcceleratorIds(snapshot.accelerators);

    return CatalogueSurface(
      key: const Key('llm-runner-combine'),
      baseColor: context.glass.cardSolid,
      padding: EdgeInsets.zero,
      borderColor: canCombine
          ? Brand.accent.withValues(alpha: 0.45)
          : onSurface.withValues(alpha: 0.14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (!canCombine) {
              promptCombineAcceleratorsLocked(context);
              return;
            }
            ref
                .read(llmRunnerStoredSelectionProvider.notifier)
                .setIds(selectable);
          },
          borderRadius: BorderRadius.circular(Brand.radius),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Brand.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(Brand.radius),
                      ),
                      child: Icon(
                        canCombine ? Icons.merge_type : Icons.lock_outline,
                        size: 18,
                        color: Brand.accent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.llmRunnerCombineTitle,
                            style: TextStyle(
                              fontFamily: Brand.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.llmRunnerCombineBody,
                            style: TextStyle(
                              fontFamily: Brand.fontFamily,
                              fontSize: 13,
                              height: 1.35,
                              color: onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            composition,
                            style: TextStyle(
                              fontFamily: Brand.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _StatusPill(
                    label: canCombine
                        ? l10n.llmRunnerCombineAction
                        : l10n.llmRunnerLicenseBadge,
                    color: Brand.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Brand.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
