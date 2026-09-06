import 'package:flutter/material.dart';

import '../brand.dart';
import '../l10n/app_localizations.dart';

class CoreClaimSlice {
  const CoreClaimSlice({
    required this.name,
    required this.kind,
    required this.cpus,
  });

  final String name;
  final String kind;
  final int cpus;
}

/// Packs scheduler CPU claims onto host cores for a color-coded allocation grid.
///
/// The daemon does not pin workloads to physical cores; this is a deterministic
/// first-fit visualization of claimed vCPU counts across [hostCpus] slots.
class CoreAllocationGraph extends StatelessWidget {
  const CoreAllocationGraph({
    required this.hostCpus,
    required this.claims,
    this.serviceNames = const {},
    this.compact = false,
    super.key,
  });

  final int hostCpus;
  final List<CoreClaimSlice> claims;
  final Set<String> serviceNames;
  final bool compact;

  static Color colorFor({
    required String kind,
    required bool isService,
  }) {
    if (kind == 'llm') return Brand.workloadAi;
    if (isService || kind == 'service') return Brand.workloadService;
    return Brand.workloadVm;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cores = hostCpus.clamp(0, 256);
    if (cores == 0) {
      return Text(
        l10n.overviewCoreAllocUnavailable,
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          fontSize: 12,
          color: onSurface.withValues(alpha: 0.55),
        ),
      );
    }

    final freeColor = onSurface.withValues(alpha: 0.12);
    final slots = List<_CoreSlot?>.filled(cores, null);
    final ordered = [...claims]..sort((a, b) {
        final byKind = a.kind.compareTo(b.kind);
        if (byKind != 0) return byKind;
        return a.name.compareTo(b.name);
      });

    var cursor = 0;
    for (final claim in ordered) {
      final isService = serviceNames.contains(claim.name);
      final color = colorFor(
        kind: claim.kind,
        isService: isService,
      );
      final count = claim.cpus.clamp(0, cores);
      for (var i = 0; i < count && cursor < cores; i++, cursor++) {
        slots[cursor] = _CoreSlot(
          index: cursor,
          name: claim.name,
          kind: isService ? 'service' : claim.kind,
          color: color,
        );
      }
    }
    for (var i = 0; i < cores; i++) {
      slots[i] ??= _CoreSlot(
        index: i,
        name: null,
        kind: 'free',
        color: freeColor,
      );
    }

    var vmCores = 0;
    var llmCores = 0;
    var serviceCores = 0;
    var freeCores = 0;
    for (final slot in slots) {
      switch (slot?.kind) {
        case 'vm':
          vmCores++;
        case 'llm':
          llmCores++;
        case 'service':
          serviceCores++;
        default:
          freeCores++;
      }
    }

    final claimed = cores - freeCores;
    final cell = compact ? 14.0 : 18.0;
    final gap = compact ? 3.0 : 4.0;
    final legendStyle = TextStyle(
      fontFamily: Brand.fontFamily,
      fontSize: 11,
      height: 1.35,
      color: onSurface.withValues(alpha: 0.7),
    );
    final legendItems = <(Color, String)>[
      if (vmCores > 0)
        (Brand.workloadVm, l10n.overviewCoreAllocLegendVms(vmCores)),
      if (llmCores > 0)
        (Brand.workloadAi, l10n.overviewCoreAllocLegendLlms(llmCores)),
      if (serviceCores > 0)
        (
          Brand.workloadService,
          l10n.overviewCoreAllocLegendServices(serviceCores),
        ),
      (freeColor, l10n.overviewCoreAllocLegendFreeCount(freeCores)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.overviewCoreAllocTitle,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
            ),
            Text(
              l10n.overviewCoreAllocSummary(claimed, cores),
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 10 : 12),
        Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final slot in slots)
              Tooltip(
                message: slot!.name == null
                    ? l10n.overviewCoreAllocFree(slot.index + 1)
                    : l10n.overviewCoreAllocClaimed(
                        slot.index + 1,
                        slot.name!,
                      ),
                waitDuration: const Duration(milliseconds: 250),
                child: MouseRegion(
                  cursor: SystemMouseCursors.basic,
                  child: Container(
                    width: cell,
                    height: cell,
                    decoration: BoxDecoration(
                      color: slot.color,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: onSurface.withValues(
                          alpha: slot.name == null ? 0.08 : 0.18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (claimed > 0) ...[
          SizedBox(height: compact ? 10 : 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final item in legendItems)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: item.$1,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: onSurface.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(item.$2, style: legendStyle),
                  ],
                ),
            ],
          ),
        ] else ...[
          SizedBox(height: compact ? 8 : 10),
          Text(
            l10n.overviewCoreAllocEmpty,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 12,
              color: onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}

class _CoreSlot {
  const _CoreSlot({
    required this.index,
    required this.name,
    required this.kind,
    required this.color,
  });

  final int index;
  final String? name;
  final String kind;
  final Color color;
}
