import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand.dart';
import '../distro_branding.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/card_action_row.dart';
import '../widgets/launchpad_button.dart';
import 'catalogue.dart';
import 'catalogue_entry.dart';
import 'catalogue_launch.dart';
import 'catalogue_surface.dart';
import 'launch_form.dart';

class ImageCard extends ConsumerStatefulWidget {
  const ImageCard({
    required this.entry,
    required this.width,
    this.locked = false,
    super.key,
  });

  final CatalogueEntry entry;
  final double width;
  final bool locked;

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

    final locked = widget.locked;

    return Opacity(
      opacity: locked ? 0.48 : 1,
      child: AbsorbPointer(
        absorbing: locked,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: SizedBox(
            width: widget.width,
            child: CatalogueSurface(
              borderColor: locked
                  ? null
                  : (_hovered ? Brand.primary.withValues(alpha: 0.45) : null),
              borderWidth: _hovered && !locked ? 1.5 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Stack(
                            alignment: Alignment.topRight,
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
                              if (locked)
                                Icon(
                                  Icons.lock_outline,
                                  size: 16,
                                  color: onSurface.withValues(alpha: 0.55),
                                ),
                            ],
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
                            enabled: !locked,
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
                  CardActionRow(
                    actions: [
                      CardAction(
                        label: l10n.commonLaunch,
                        kind: LaunchPadButtonKind.primary,
                        onTap: () =>
                            launchCatalogueImage(context, ref, selectedImage),
                      ),
                      CardAction(
                        label: l10n.cloudInitLaunchCardButton,
                        onTap: () {
                          configureCatalogueImage(
                            ref,
                            selectedImage,
                            requireCloudInit: true,
                          );
                          Scaffold.of(context).openEndDrawer();
                        },
                      ),
                      CardAction(
                        label: l10n.commonConfigure,
                        onTap: () {
                          configureCatalogueImage(ref, selectedImage);
                          Scaffold.of(context).openEndDrawer();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionSelector extends ConsumerWidget {
  const _VersionSelector({
    required this.entry,
    required this.selectedImage,
    this.enabled = true,
  });

  final CatalogueEntry entry;
  final ImageInfo selectedImage;
  final bool enabled;

  static const _height = 34.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fill = Theme.of(context).inputDecorationTheme.fillColor ??
        onSurface.withValues(alpha: 0.08);
    final canSelect = enabled && entry.versions.length > 1;
    final label = catalogueVersionLabel(selectedImage);

    return SizedBox(
      height: _height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: canSelect ? fill : onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(Brand.radius),
          border: Border.all(
            color: onSurface.withValues(alpha: canSelect ? 0.22 : 0.12),
          ),
        ),
        child: canSelect
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

