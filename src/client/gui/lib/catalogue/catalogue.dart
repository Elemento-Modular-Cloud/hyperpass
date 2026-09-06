import 'dart:math';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';
import 'package:intersperse/intersperse.dart';

import '../auth/feature_access.dart';
import '../brand.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/rounded_search_field.dart';
import 'catalogue_entry.dart';
import 'image_card.dart';
import 'launch_form.dart';

class SelectedImageNotifier extends Notifier<ImageInfo?> {
  SelectedImageNotifier(this.arg);
  final String arg;

  @override
  ImageInfo? build() => null;

  void set(ImageInfo image) => state = image;
}

final selectedImageProvider =
    NotifierProvider.family<SelectedImageNotifier, ImageInfo?, String>(
  SelectedImageNotifier.new,
);

class CatalogueSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final catalogueSearchProvider =
    NotifierProvider<CatalogueSearchNotifier, String>(
  CatalogueSearchNotifier.new,
);

final imagesProvider = FutureProvider<List<ImageInfo>>((ref) async {
  if (!ref.watch(daemonAvailableProvider)) {
    return [];
  }

  return ref
      .watch(grpcClientProvider)
      .find()
      .then((reply) => sortImages(reply.imagesInfo));
});

class CatalogueScreen extends ConsumerStatefulWidget {
  static const sidebarKey = 'catalogue';

  const CatalogueScreen({super.key});

  @override
  ConsumerState<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends ConsumerState<CatalogueScreen> {
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
      endDrawer: const LaunchForm(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 720) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _CatalogueHeader(l10n: l10n)),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 260,
                        child: RoundedSearchField(
                          width: null,
                          controller: _searchController,
                          hint: l10n.catalogueSearchHint,
                          onChanged: (value) => ref
                              .read(catalogueSearchProvider.notifier)
                              .set(value),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CatalogueHeader(l10n: l10n),
                    const SizedBox(height: 12),
                    RoundedSearchField(
                      width: null,
                      controller: _searchController,
                      hint: l10n.catalogueSearchHint,
                      onChanged: (value) =>
                          ref.read(catalogueSearchProvider.notifier).set(value),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ref.watch(imagesProvider).when(
                    skipLoadingOnRefresh: false,
                    data: (images) => _buildGrid(context, images, l10n),
                    error: (error, _) => _buildError(context, error, l10n),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(
      BuildContext context, Object error, AppLocalizations l10n) {
    final errorMessage = error is GrpcError
        ? (error.message ?? error.toString())
        : error.toString();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.catalogueLoadError(errorMessage),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.invalidate(imagesProvider),
            child: Text(l10n.catalogueRefresh),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<ImageInfo> images,
    AppLocalizations l10n,
  ) {
    final query = ref.watch(catalogueSearchProvider).trim().toLowerCase();
    final ubuntuOnly = ref.watch(featureAccessProvider).ubuntuImagesOnly;
    final entries = groupCatalogueEntries(images)
        .where((entry) => entry.matchesQuery(query))
        .toList();

    if (entries.isEmpty) {
      return Center(
        child: Text(
          l10n.catalogueNoResults,
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
          final nCards = max(1, constraints.maxWidth ~/ minCardWidth);
          final cardWidth =
              (constraints.maxWidth - spacing * (nCards - 1)) / nCards;

          final rows = <Widget>[];
          for (var i = 0; i < entries.length; i += nCards) {
            final rowEntries = entries.skip(i).take(nCards).toList();
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < rowEntries.length; j++) ...[
                      if (j > 0) const SizedBox(width: spacing),
                      ImageCard(
                        entry: rowEntries[j],
                        width: cardWidth,
                        locked: ubuntuOnly &&
                            rowEntries[j]
                                    .representative
                                    .os
                                    .toLowerCase() !=
                                'ubuntu',
                      ),
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

class _CatalogueHeader extends StatelessWidget {
  const _CatalogueHeader({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.catalogueWelcomeTitle,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: Brand.fontFamily,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.catalogueWelcomeBody,
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
