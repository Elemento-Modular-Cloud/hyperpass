import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intersperse/intersperse.dart';

import '../brand.dart';
import '../catalogue/catalogue_surface.dart';
import '../l10n/app_localizations.dart';
import '../widgets/rounded_search_field.dart';
import 'service_branding.dart';
import 'service_deploy.dart';
import 'service_detail.dart';
import 'service_library.dart';

class ServicesSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final servicesSearchProvider = NotifierProvider<ServicesSearchNotifier, String>(
  ServicesSearchNotifier.new,
);

/// Id of the service whose detail page is open, or null for the grid.
class SelectedServiceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;

  void clear() => state = null;
}

final selectedServiceProvider =
    NotifierProvider<SelectedServiceNotifier, String?>(
  SelectedServiceNotifier.new,
);

class ServicesScreen extends ConsumerStatefulWidget {
  static const sidebarKey = 'services';

  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: ref.watch(marketplaceLibraryProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _buildError(context, error, l10n),
            data: (library) {
              final selectedId = ref.watch(selectedServiceProvider);
              final selected =
                  selectedId == null ? null : library.byId(selectedId);

              if (selected != null) {
                return ServiceDetailView(
                  service: selected,
                  onBack: () =>
                      ref.read(selectedServiceProvider.notifier).clear(),
                );
              }
              return _buildCatalogue(context, library, l10n);
            },
          ),
    );
  }

  Widget _buildError(
    BuildContext context,
    Object error,
    AppLocalizations l10n,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.servicesLoadError('$error'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref.invalidate(marketplaceLibraryProvider),
              child: Text(l10n.catalogueRefresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogue(
    BuildContext context,
    MarketplaceLibrary library,
    AppLocalizations l10n,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final search = RoundedSearchField(
                width: null,
                controller: _searchController,
                hint: l10n.servicesSearchHint,
                onChanged: (value) =>
                    ref.read(servicesSearchProvider.notifier).set(value),
              );

              if (constraints.maxWidth >= 720) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: _ServicesHeader(l10n: l10n)),
                    const SizedBox(width: 16),
                    SizedBox(width: 260, child: search),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: l10n.catalogueRefresh,
                      onPressed: () =>
                          ref.invalidate(marketplaceLibraryProvider),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _ServicesHeader(l10n: l10n)),
                      IconButton(
                        tooltip: l10n.catalogueRefresh,
                        onPressed: () =>
                            ref.invalidate(marketplaceLibraryProvider),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  search,
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Expanded(child: _buildGrid(context, library, l10n)),
        ],
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    MarketplaceLibrary library,
    AppLocalizations l10n,
  ) {
    final query = ref.watch(servicesSearchProvider).trim().toLowerCase();
    final services = library.services
        .where((service) => _matchesQuery(service, query))
        .toList();

    if (services.isEmpty) {
      return Center(
        child: Text(
          l10n.servicesNoResults,
          style: TextStyle(
            fontSize: 16,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const minCardWidth = 240.0;
          const spacing = 16.0;
          final columns = max(1, constraints.maxWidth ~/ minCardWidth);
          final cardWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;

          final rows = <Widget>[];
          for (var i = 0; i < services.length; i += columns) {
            final rowServices = services.skip(i).take(columns).toList();
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < rowServices.length; j++) ...[
                      if (j > 0) const SizedBox(width: spacing),
                      ServiceCard(service: rowServices[j], width: cardWidth),
                    ],
                  ],
                ),
              ),
            );
          }

          return Column(
            children:
                rows.intersperse(const SizedBox(height: spacing)).toList(),
          );
        },
      ),
    );
  }
}

bool _matchesQuery(MarketplaceService service, String query) {
  if (query.isEmpty) return true;
  return service.displayName.toLowerCase().contains(query) ||
      service.id.toLowerCase().contains(query) ||
      service.description.toLowerCase().contains(query);
}

class ServiceCard extends ConsumerStatefulWidget {
  const ServiceCard({required this.service, required this.width, super.key});

  final MarketplaceService service;
  final double width;

  @override
  ConsumerState<ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends ConsumerState<ServiceCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = widget.service;
    final branding = serviceBranding(service.id, service: service);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final radius = BorderRadius.circular(Brand.radius);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.width,
        child: CatalogueSurface(
          borderColor:
              branding.accent.withValues(alpha: _hovered ? 0.75 : 0.35),
          borderWidth: _hovered ? 1.5 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => ref
                      .read(selectedServiceProvider.notifier)
                      .select(service.id),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: ServiceIconBadge(
                            branding: branding,
                            size: 40,
                            semanticsLabel: service.displayName,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          service.displayName,
                          style: TextStyle(
                            fontFamily: Brand.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: onSurface,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          service.description,
                          style: TextStyle(
                            fontFamily: Brand.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w300,
                            height: 1.3,
                            color: onSurface.withValues(alpha: 0.7),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        const SizedBox(height: 8),
                        // The id disambiguates services that share a display
                        // name, e.g. n8n, n8n_v2 and n8n_v3.
                        Text(
                          '${service.id} · ${service.version}',
                          style: TextStyle(
                            fontFamily: Brand.fontFamily,
                            fontSize: 11,
                            color: onSurface.withValues(alpha: 0.55),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _ServiceCardActions(
                radius: radius,
                onDetails: () => ref
                    .read(selectedServiceProvider.notifier)
                    .select(service.id),
                onDeploy: () => showServiceDeployDialog(context, service),
                detailsLabel: l10n.servicesCardDetails,
                deployLabel: l10n.serviceDeployAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceCardActions extends StatelessWidget {
  const _ServiceCardActions({
    required this.radius,
    required this.onDetails,
    required this.onDeploy,
    required this.detailsLabel,
    required this.deployLabel,
  });

  final BorderRadius radius;
  final VoidCallback onDetails;
  final VoidCallback onDeploy;
  final String detailsLabel;
  final String deployLabel;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;

    Widget action({
      required VoidCallback onTap,
      required String label,
      required BorderRadius borderRadius,
      Color? color,
      Color? textColor,
      FontWeight weight = FontWeight.w500,
      bool topBorder = false,
    }) {
      return Expanded(
        child: Material(
          color: color ?? Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border:
                    topBorder ? Border(top: BorderSide(color: divider)) : null,
                borderRadius: borderRadius,
              ),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 12,
                    fontWeight: weight,
                    color: textColor ?? onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          action(
            onTap: onDeploy,
            label: deployLabel,
            borderRadius: BorderRadius.only(bottomLeft: radius.bottomLeft),
            color: Brand.accent,
            weight: FontWeight.w600,
            textColor: Brand.voidBlack,
          ),
          Container(width: 1, color: divider),
          action(
            onTap: onDetails,
            label: detailsLabel,
            borderRadius: BorderRadius.only(bottomRight: radius.bottomRight),
            topBorder: true,
          ),
        ],
      ),
    );
  }
}

class _ServicesHeader extends StatelessWidget {
  const _ServicesHeader({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.servicesLabel,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: Brand.fontFamily,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.servicesSubtitle,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w300,
            height: 1.35,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
            fontFamily: Brand.fontFamily,
          ),
        ),
      ],
    );
  }
}
