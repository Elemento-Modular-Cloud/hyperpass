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
                        child: _DistroLogoBadge(
                          branding: branding,
                          os: widget.entry.representative.os,
                          size: 40,
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
                onConfigure: () {
                  configureCatalogueImage(ref, selectedImage);
                  Scaffold.of(context).openEndDrawer();
                },
                launchLabel: l10n.commonLaunch,
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
    required this.onConfigure,
    required this.launchLabel,
    required this.configureLabel,
  });

  final BorderRadius radius;
  final VoidCallback onLaunch;
  final VoidCallback onConfigure;
  final String launchLabel;
  final String configureLabel;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;

    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Material(
              color: Brand.yellow,
              borderRadius: BorderRadius.only(
                bottomLeft: radius.bottomLeft,
              ),
              child: InkWell(
                onTap: onLaunch,
                borderRadius: BorderRadius.only(
                  bottomLeft: radius.bottomLeft,
                ),
                child: Center(
                  child: Text(
                    launchLabel,
                    style: const TextStyle(
                      fontFamily: Brand.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Brand.voidBlack,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(width: 1, color: divider),
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.only(
                bottomRight: radius.bottomRight,
              ),
              child: InkWell(
                onTap: onConfigure,
                borderRadius: BorderRadius.only(
                  bottomRight: radius.bottomRight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: divider),
                    ),
                    borderRadius: BorderRadius.only(
                      bottomRight: radius.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      configureLabel,
                      style: TextStyle(
                        fontFamily: Brand.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
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

class _DistroLogoBadge extends StatelessWidget {
  const _DistroLogoBadge({
    required this.branding,
    required this.os,
    required this.size,
  });

  final DistroBranding branding;
  final String os;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRaster = distroLogoIsRaster(branding.logoAsset);
    final Color badgeFill;
    if (branding.logoBackground != null) {
      badgeFill = branding.logoBackground!;
    } else if (isRaster) {
      badgeFill = Colors.transparent;
    } else {
      badgeFill = branding.accent.withValues(alpha: 0.12);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: badgeFill,
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: branding.accent.withValues(alpha: 0.45)),
      ),
      padding: EdgeInsets.all(isRaster ? size * 0.08 : size * 0.18),
      child: distroLogoPicture(
        branding,
        size: size,
        semanticsLabel: l10n.imageCardLogoSemantics(os),
        colorFilter: branding.logoTint == null
            ? null
            : ColorFilter.mode(branding.logoTint!, BlendMode.srcIn),
      ),
    );
  }
}
