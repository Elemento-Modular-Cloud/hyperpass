import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand.dart';
import '../catalogue/catalogue_surface.dart';
import '../catalogue/launch_form.dart' show formatDiskSize;
import '../l10n/app_localizations.dart';
import '../page_surface.dart';
import 'service_branding.dart';
import 'service_cloud_init.dart';
import 'service_deploy.dart';
import 'service_library.dart';

class ServiceDetailView extends ConsumerWidget {
  const ServiceDetailView({
    required this.service,
    required this.onBack,
    super.key,
  });

  final MarketplaceService service;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final branding = serviceBranding(service.id, service: service);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return PageSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(l10n.serviceBackToCatalog),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ServiceIconBadge(branding: branding, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.displayName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: Brand.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${service.id} · ${l10n.serviceVersion(service.version)}',
                      style: TextStyle(
                        fontFamily: Brand.fontFamily,
                        fontSize: 12,
                        color: onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (service.description.isNotEmpty)
                    Text(
                      service.description,
                      style: TextStyle(
                        fontFamily: Brand.fontFamily,
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w300,
                        color: onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _ActionRow(service: service),
                  const SizedBox(height: 24),
                  _Section(
                    title: l10n.serviceRequirementsTitle,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          accent: branding.accent,
                          label: l10n.serviceRequirementCpus(
                            serviceCpus(service),
                          ),
                        ),
                        _InfoChip(
                          accent: branding.accent,
                          label: l10n.serviceRequirementMemory(
                            formatDiskSize(serviceMemoryBytes(service)),
                          ),
                        ),
                        _InfoChip(
                          accent: branding.accent,
                          label: l10n.serviceRequirementDisk(
                            formatDiskSize(serviceDiskBytes(service)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Section(
                    title: l10n.servicePortsTitle,
                    child: service.exposedPorts.isEmpty
                        ? _MutedText(l10n.servicePortsNone)
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final port in service.exposedPorts)
                                _InfoChip(
                                  accent: branding.accent,
                                  label: '$port',
                                ),
                            ],
                          ),
                  ),
                  if (service.storage.isNotEmpty)
                    _Section(
                      title: l10n.serviceStorageTitle,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in service.storage)
                            _BulletRow(
                              text: l10n.serviceStorageEntry(
                                entry.path,
                                entry.minSizeGb,
                              ),
                              detail: entry.description,
                            ),
                        ],
                      ),
                    ),
                  if (service.healthcheck != null ||
                      service.serviceInfo != null)
                    _Section(
                      title: l10n.serviceRuntimeTitle,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (service.healthcheck != null)
                            _BulletRow(
                              text: l10n.serviceRuntimeHealthcheck(
                                service.healthcheck!,
                              ),
                            ),
                          if (service.serviceInfo != null)
                            _BulletRow(
                              text: l10n.serviceRuntimeServiceInfo(
                                service.serviceInfo!,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (service.variables.isNotEmpty)
                    _Section(
                      title: l10n.serviceParametersTitle,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MutedText(
                            '${l10n.serviceParametersCount(service.variables.length)}'
                            ' · ${l10n.serviceParametersOptional}',
                          ),
                          const SizedBox(height: 10),
                          for (final variable in service.variables)
                            _BulletRow(
                              text: variable.label,
                              detail: variable.documentation,
                              mono: true,
                            ),
                        ],
                      ),
                    ),
                  if (service.files.isNotEmpty)
                    _Section(
                      title: l10n.serviceFilesTitle(service.files.length),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final file in service.files)
                            _BulletRow(text: file.destination, mono: true),
                        ],
                      ),
                    ),
                  if (service.readme != null)
                    _Section(
                      title: l10n.serviceDocsTitle,
                      child: CatalogueSurface(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          service.readme!.trim(),
                          style: TextStyle(
                            fontFamily: 'UbuntuMono',
                            fontSize: 12,
                            height: 1.45,
                            color: onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.service});

  final MarketplaceService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        TextButton(
          onPressed: () => showServiceDeployDialog(context, service),
          child: Text(l10n.serviceDeployAction),
        ),
        OutlinedButton(
          onPressed: () => _showCloudInit(context),
          child: Text(l10n.serviceViewCloudInit),
        ),
        OutlinedButton(
          onPressed: () => _saveCloudInit(context, ref),
          child: Text(l10n.serviceSaveCloudInit),
        ),
      ],
    );
  }

  void _showCloudInit(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final String rendered;
    try {
      rendered = renderServiceCloudInit(service);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.serviceDeployFailure(service.displayName, '$error'),
          ),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: const Border(),
        title: Row(
          children: [
            Expanded(
              child: Text(l10n.serviceCloudInitTitle(service.displayName)),
            ),
            IconButton(
              onPressed: () => Navigator.pop(dialogContext),
              splashRadius: 15,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 720,
          height: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              rendered,
              style: TextStyle(
                fontFamily: 'UbuntuMono',
                fontSize: 12,
                height: 1.4,
                color: onSurface,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCloudInit(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final name = await saveServiceCloudInit(ref, service);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.serviceSaveCloudInitSuccess(name))),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.serviceSaveCloudInitFailure('$error'))),
      );
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.text, this.detail, this.mono = false});

  final String text;
  final String? detail;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontFamily: mono ? 'UbuntuMono' : Brand.fontFamily,
                    fontSize: 13,
                    color: onSurface.withValues(alpha: 0.85),
                  ),
                ),
                if (detail != null && detail!.isNotEmpty)
                  Text(
                    detail!,
                    style: TextStyle(
                      fontFamily: Brand.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: Brand.fontFamily,
        fontSize: 13,
        height: 1.4,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
      ),
    );
  }
}
