import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand.dart';
import '../distro_branding.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'catalogue.dart';
import 'catalogue_entry.dart';
import 'catalogue_launch.dart';
import 'catalogue_surface.dart';
import 'launch_form.dart';

class ImageCard extends ConsumerStatefulWidget {
  const ImageCard({
    required this.entry,
    required this.width,
    super.key,
  });

  final CatalogueEntry entry;
  final double width;

  @override
  ConsumerState<ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends ConsumerState<ImageCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final branding = distroBranding(
      widget.entry.representative.os,
      isCore: widget.entry.isCore,
    );
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final key = widget.entry.key;
    final selectedImage =
        ref.watch(selectedImageProvider(key)) ?? widget.entry.defaultImage;

    if (ref.read(selectedImageProvider(key)) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(selectedImageProvider(key).notifier)
              .set(widget.entry.defaultImage);
        }
      });
    }

    final radius = BorderRadius.circular(Brand.radius);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.width,
        child: CatalogueSurface(
          borderColor: _hovered
              ? branding.accent.withValues(alpha: 0.75)
              : branding.accent.withValues(alpha: 0.35),
          borderWidth: _hovered ? 1.5 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: DistroLogoBadge(
                          branding: branding,
                          size: 40,
                          semanticsLabel: l10n.imageCardLogoSemantics(
                            widget.entry.representative.os,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.entry.displayTitle(l10n),
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
                        widget.entry.description(l10n),
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w300,
                          height: 1.3,
                          color: onSurface.withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      _VersionSelector(
                        entry: widget.entry,
                        selectedImage: selectedImage,
                        accent: branding.accent,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.imageCardMinDisk(
                          formatDiskSize(diskBytesForImage(selectedImage)),
                        ),
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
              _CardActionBar(
                radius: radius,
                onLaunch: () =>
                    launchCatalogueImage(context, ref, selectedImage),
                onCloudInit: () {
                  configureCatalogueImage(
                    ref,
                    selectedImage,
                    requireCloudInit: true,
                  );
                  Scaffold.of(context).openEndDrawer();
                },
                onConfigure: () {
                  configureCatalogueImage(ref, selectedImage);
                  Scaffold.of(context).openEndDrawer();
                },
                launchLabel: l10n.commonLaunch,
                cloudInitLabel: l10n.cloudInitLaunchCardButton,
                configureLabel: l10n.commonConfigure,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardActionBar extends StatelessWidget {
  const _CardActionBar({
    required this.radius,
    required this.onLaunch,
    required this.onCloudInit,
    required this.onConfigure,
    required this.launchLabel,
    required this.cloudInitLabel,
    required this.configureLabel,
  });

  final BorderRadius radius;
  final VoidCallback onLaunch;
  final VoidCallback onCloudInit;
  final VoidCallback onConfigure;
  final String launchLabel;
  final String cloudInitLabel;
  final String configureLabel;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;

    Widget action({
      required VoidCallback onTap,
      required String label,
      required BorderRadius borderRadius,
      Color? color,
      FontWeight weight = FontWeight.w500,
      Color? textColor,
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
                border: topBorder
                    ? Border(top: BorderSide(color: divider))
                    : null,
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
            onTap: onLaunch,
            label: launchLabel,
            borderRadius: BorderRadius.only(bottomLeft: radius.bottomLeft),
            color: Brand.accent,
            weight: FontWeight.w600,
            textColor: Brand.voidBlack,
          ),
          Container(width: 1, color: divider),
          action(
            onTap: onCloudInit,
            label: cloudInitLabel,
            borderRadius: BorderRadius.zero,
            topBorder: true,
          ),
          Container(width: 1, color: divider),
          action(
            onTap: onConfigure,
            label: configureLabel,
            borderRadius: BorderRadius.only(bottomRight: radius.bottomRight),
            topBorder: true,
          ),
        ],
      ),
    );
  }
}

class _VersionSelector extends ConsumerWidget {
  const _VersionSelector({
    required this.entry,
    required this.selectedImage,
    required this.accent,
  });

  final CatalogueEntry entry;
  final ImageInfo selectedImage;
  final Color accent;

  static const _height = 34.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fill = Theme.of(context).inputDecorationTheme.fillColor ??
        onSurface.withValues(alpha: 0.08);
    final enabled = entry.versions.length > 1;
    final label = catalogueVersionLabel(selectedImage);

    return SizedBox(
      height: _height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled ? fill : onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(Brand.radius),
          border: Border.all(
            color: accent.withValues(alpha: enabled ? 0.35 : 0.2),
          ),
        ),
        child: enabled
            ? DropdownButtonHideUnderline(
                child: ButtonTheme(
                  alignedDropdown: true,
                  child: DropdownButton<String>(
                    value: selectedImage.release,
                    isExpanded: true,
                    isDense: true,
                    borderRadius: BorderRadius.circular(Brand.radius),
                    menuMaxHeight: 240,
                    icon: Icon(
                      Icons.expand_more,
                      size: 18,
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    style: TextStyle(
                      fontFamily: Brand.fontFamily,
                      fontSize: 12,
                      color: onSurface,
                    ),
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    items: entry.versions
                        .map(
                          (version) => DropdownMenuItem(
                            value: version.release,
                            child: Text(
                              catalogueVersionLabel(version),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (release) {
                      if (release == null) return;
                      final version = entry.versions
                          .firstWhere((v) => v.release == release);
                      ref
                          .read(selectedImageProvider(entry.key).notifier)
                          .set(version);
                    },
                    selectedItemBuilder: (context) => entry.versions
                        .map(
                          (version) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              catalogueVersionLabel(version),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: Brand.fontFamily,
                                fontSize: 12,
                                color: onSurface,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      size: 18,
                      color: onSurface.withValues(alpha: 0.25),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

