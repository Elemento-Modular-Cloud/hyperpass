import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brand.dart';
import '../../catalogue/catalogue_surface.dart';
import '../../l10n/app_localizations.dart';
import '../../page_surface.dart';
import '../../providers.dart';
import '../providers.dart';

/// Local tool installers (llmfit, llama.cpp) — status + install per card.
class LlmSetupScreen extends ConsumerWidget {
  static const sidebarKey = 'llm-setup';

  const LlmSetupScreen({super.key});

  static const _primaryBackendIds = ['llmfit', 'llamacpp'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final backends = ref.watch(llmBackendsProvider);
    final installs = ref.watch(llmBackendInstallsProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageSurface(
        baseColor: context.glass.cardSolid,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.llmSetupLabel,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: 37,
                          fontWeight: FontWeight.w300,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.llmSetupSubtitle,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: 13,
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => ref.invalidate(llmBackendsProvider),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(l10n.modelsBackendsRefresh),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: backends.when(
                data: (reply) {
                  final byId = {
                    for (final b in reply.backends) b.id: b,
                  };
                  final cards = <LlmBackendInfo>[
                    for (final id in _primaryBackendIds)
                      if (byId.containsKey(id)) byId[id]!,
                    ...reply.backends.where(
                      (b) =>
                          !_primaryBackendIds.contains(b.id) &&
                          (b.installable || b.required),
                    ),
                  ];
                  if (cards.isEmpty) {
                    return Text(
                      l10n.llmSetupEmpty,
                      style: TextStyle(
                        fontFamily: Brand.fontFamily,
                        color: onSurface.withValues(alpha: 0.7),
                      ),
                    );
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 720;
                      final children = [
                        for (final backend in cards)
                          _BackendInstallCard(
                            backend: backend,
                            progressPercent: installs[backend.id],
                          ),
                      ];
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < children.length; i++) ...[
                              if (i > 0) const SizedBox(width: 16),
                              Expanded(child: children[i]),
                            ],
                          ],
                        );
                      }
                      return ListView.separated(
                        itemCount: children.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) => children[i],
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('$e'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackendInstallCard extends ConsumerWidget {
  const _BackendInstallCard({
    required this.backend,
    this.progressPercent,
  });

  final LlmBackendInfo backend;
  final int? progressPercent;

  bool get _installing => progressPercent != null;
  bool get _ready => backend.status == 'ready';
  bool get _canInstall =>
      backend.installable && !_ready && !_installing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final title = backend.name.isEmpty ? backend.id : backend.name;
    final statusLabel = _installing
        ? l10n.llmSetupInstalling
        : _ready
            ? l10n.modelsBackendStatusReady
            : l10n.modelsBackendStatusMissing;
    final statusColor = _installing
        ? Brand.accent
        : _ready
            ? Brand.green
            : scheme.error;

    final detail = [
      if (backend.detail.isNotEmpty) backend.detail,
      if (backend.binaryPath.isNotEmpty) backend.binaryPath,
      if (!_ready && backend.installHint.isNotEmpty) backend.installHint,
    ].join('\n');

    return CatalogueSurface(
      baseColor: context.glass.cardSolid,
      padding: const EdgeInsets.all(20),
      borderColor: statusColor.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                _ready
                    ? Icons.check_circle
                    : _installing
                        ? Icons.downloading
                        : Icons.error_outline,
                size: 22,
                color: statusColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _backendBlurb(l10n, backend.id),
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 13,
              height: 1.35,
              color: onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              detail,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 11,
                height: 1.35,
                color: onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
          if (_installing) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (progressPercent ?? 0) > 0
                  ? (progressPercent!.clamp(0, 100) / 100.0)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              '${(progressPercent ?? 0).clamp(0, 100)}%',
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 11,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: _canInstall
                ? FilledButton.icon(
                    onPressed: () => ref
                        .read(llmBackendInstallsProvider.notifier)
                        .install(backend.id),
                    icon: const Icon(Icons.download, size: 16),
                    label: Text(l10n.modelsBackendsInstall),
                  )
                : _ready
                    ? Text(
                        l10n.llmSetupReadyHint,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.55),
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _backendBlurb(AppLocalizations l10n, String id) {
    return switch (id) {
      'llmfit' => l10n.llmSetupLlmfitBlurb,
      'llamacpp' => l10n.llmSetupLlamacppBlurb,
      _ => l10n.modelsBackendsHint,
    };
  }
}
