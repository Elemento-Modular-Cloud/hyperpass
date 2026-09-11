import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Switch;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../appearance_settings.dart';
import '../background_providers.dart';
import '../brand.dart';
import '../catalogue/catalogue_surface.dart';
import '../hsv_colour_picker.dart';
import '../l10n/app_localizations.dart';
import '../switch.dart';
import '../widgets/launchpad_button.dart';
import '../wallpaper_store.dart';

class AppearanceSettingsSection extends ConsumerWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final appearance = ref.watch(appearanceSettingsProvider);
    final notifier = ref.read(appearanceSettingsProvider.notifier);
    final wallpapersAsync = ref.watch(storedWallpapersProvider);
    final storeAsync = ref.watch(wallpaperStoreProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.appearanceTitle,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        CatalogueSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.appearanceGlassTitle,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Switch(
                label: l10n.appearanceGlassToggle,
                value: appearance.useGlassmorphism,
                trailingSwitch: true,
                onChanged: notifier.setUseGlassmorphism,
              ),
              if (appearance.useGlassmorphism) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.appearanceThemeLabel,
                  style: TextStyle(color: onSurface, fontSize: 14),
                ),
                const SizedBox(height: 8),
                _ThemePicker(
                  selected: appearance.theme,
                  onSelected: (theme) =>
                      notifier.setTheme(theme, autoSelected: false),
                ),
              ] else ...[
                const SizedBox(height: 16),
                _ColourRow(
                  label: l10n.appearanceCardColourLabel,
                  colour: appearance.cardColorValue,
                  onChanged: notifier.setCardColour,
                ),
                const SizedBox(height: 12),
                _SliderRow(
                  label: l10n.appearanceCardOpacityLabel,
                  value: appearance.cardOpacity,
                  onChanged: notifier.setCardOpacity,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        CatalogueSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.appearanceBackgroundTitle,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Switch(
                label: l10n.appearanceBackgroundAnimations,
                value: appearance.animate,
                trailingSwitch: true,
                onChanged: notifier.setAnimateBackground,
              ),
              const SizedBox(height: 8),
              Switch(
                label: l10n.appearanceAtmosphereToggle,
                value: appearance.wallpaperType == WallpaperType.atmosphere,
                trailingSwitch: true,
                onChanged: (value) {
                  if (value) {
                    notifier.setAtmosphereWallpaper();
                  } else {
                    notifier.setNoneWallpaper();
                  }
                },
              ),
              const SizedBox(height: 16),
              Text(
                l10n.appearanceWallpaperLabel,
                style: TextStyle(color: onSurface, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _AssetWallpaperTile(
                    label: l10n.appearanceWallpaperDefault,
                    selected: appearance.wallpaperType ==
                            WallpaperType.image &&
                        isBundledWallpaper(appearance.wallpaper),
                    onTap: notifier.setDefaultWallpaper,
                  ),
                  _WallpaperTile(
                    label: l10n.appearanceWallpaperNone,
                    icon: Icons.block,
                    selected: appearance.wallpaperType == WallpaperType.none,
                    onTap: () async {
                      await notifier.setNoneWallpaper();
                    },
                  ),
                  _WallpaperColourTile(
                    label: l10n.appearanceWallpaperColour,
                    colour: appearance.wallpaperColor ??
                        const Color(0xFF1A1A2E),
                    selected: appearance.wallpaperType == WallpaperType.colour,
                    onColourChanged: notifier.setColourWallpaper,
                  ),
                  _WallpaperTile(
                    label: l10n.appearanceWallpaperImport,
                    icon: Icons.add_photo_alternate_outlined,
                    selected: false,
                    onTap: () async {
                      const typeGroup = XTypeGroup(
                        label: 'images',
                        extensions: ['jpg', 'jpeg', 'png', 'webp'],
                      );
                      final file = await openFile(
                        acceptedTypeGroups: const [typeGroup],
                      );
                      if (file?.path != null) {
                        await notifier.importImageWallpaper(file!.path);
                        ref.invalidate(storedWallpapersProvider);
                      }
                    },
                  ),
                  for (final provider in BackgroundProviderService.providers)
                    _ProviderWallpaperTile(
                      provider: provider,
                      selected: appearance.wallpaperType ==
                              WallpaperType.provider &&
                          appearance.wallpaper == provider.reference,
                      onTap: () => notifier.setProviderWallpaper(
                        provider.reference,
                      ),
                    ),
                  ...?wallpapersAsync.whenOrNull(
                    data: (files) => files.map(
                      (file) => _StoredWallpaperTile(
                        file: file,
                        selected: appearance.wallpaperType ==
                                WallpaperType.image &&
                            appearance.wallpaper == file.path,
                        onTap: () => notifier.setImageWallpaper(file.path),
                        onDelete: () async {
                          await WallpaperStore.open().then((store) async {
                            await store.delete(file.path);
                          });
                          if (appearance.wallpaper == file.path) {
                            await notifier.setNoneWallpaper();
                          }
                          ref.invalidate(storedWallpapersProvider);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              storeAsync.when(
                data: (store) => Text(
                  l10n.appearanceWallpaperHint(store.displayPath),
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontFamily: Brand.fontFamily,
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              if ({WallpaperType.image, WallpaperType.provider}
                  .contains(appearance.wallpaperType)) ...[
                const SizedBox(height: 16),
                _SliderRow(
                  label: l10n.appearanceWallpaperBrightness,
                  value: appearance.wallpaperBrightness,
                  min: 20,
                  max: 150,
                  suffix: '%',
                  onChanged: notifier.setWallpaperBrightness,
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  label: l10n.appearanceWallpaperBlur,
                  value: appearance.wallpaperBlur,
                  max: 30,
                  suffix: 'px',
                  onChanged: notifier.setWallpaperBlur,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({
    required this.selected,
    required this.onSelected,
  });

  final AppearanceTheme selected;
  final ValueChanged<AppearanceTheme> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      children: [
        _ThemeButton(
          label: l10n.appearanceThemeLight,
          background: Brand.white,
          foreground: Brand.greyDarker,
          selected: selected == AppearanceTheme.light,
          onTap: () => onSelected(AppearanceTheme.light),
        ),
        _ThemeButton(
          label: l10n.appearanceThemeDark,
          background: Brand.black,
          foreground: Brand.crystalWhite,
          selected: selected == AppearanceTheme.dark,
          onTap: () => onSelected(AppearanceTheme.dark),
        ),
        _ThemeButton(
          label: l10n.appearanceThemeMidnight,
          background: Colors.black,
          foreground: Brand.accent,
          selected: selected == AppearanceTheme.highContrast,
          onTap: () => onSelected(AppearanceTheme.highContrast),
        ),
      ],
    );
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(Brand.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            border: Border.all(
              color: selected ? Brand.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontFamily: Brand.fontFamily,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssetWallpaperTile extends StatelessWidget {
  const _AssetWallpaperTile({
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Container(
          width: 100,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            border: Border.all(
              color: selected ? Brand.accent : onSurface.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
            image: const DecorationImage(
              image: AssetImage(kDefaultWallpaperAsset),
              fit: BoxFit.cover,
            ),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(Brand.radius - 1),
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontFamily: Brand.fontFamily,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Container(
          width: 100,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            border: Border.all(
              color: selected ? Brand.accent : onSurface.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: onSurface, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 11,
                  fontFamily: Brand.fontFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderWallpaperTile extends StatelessWidget {
  const _ProviderWallpaperTile({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final BackgroundProviderInfo provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Container(
          width: 100,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            border: Border.all(
              color: selected ? Brand.accent : onSurface.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(provider.icon, color: onSurface, size: 22),
              const SizedBox(height: 4),
              Text(
                provider.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 10,
                  fontFamily: Brand.fontFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoredWallpaperTile extends StatelessWidget {
  const _StoredWallpaperTile({
    required this.file,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final File file;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Container(
          width: 100,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            border: Border.all(
              color: selected ? Brand.accent : Colors.white24,
              width: selected ? 2 : 1,
            ),
            image: DecorationImage(
              image: FileImage(file),
              fit: BoxFit.cover,
            ),
          ),
          child: Align(
            alignment: Alignment.topRight,
            child: IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: onDelete,
            ),
          ),
        ),
      ),
    );
  }
}

class _WallpaperColourTile extends StatelessWidget {
  const _WallpaperColourTile({
    required this.label,
    required this.colour,
    required this.selected,
    required this.onColourChanged,
  });

  final String label;
  final Color colour;
  final bool selected;
  final Future<void> Function(Color) onColourChanged;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: colour,
      borderRadius: BorderRadius.circular(Brand.radius),
      child: InkWell(
        onTap: () async {
          final picked = await showDialog<Color>(
            context: context,
            builder: (context) => _SimpleColourPicker(initial: colour),
          );
          if (picked != null) {
            await onColourChanged(picked);
          }
        },
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Container(
          width: 100,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            border: Border.all(
              color: selected ? Brand.accent : onSurface.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              color: colour.computeLuminance() > 0.5 ? Colors.black : Colors.white,
              fontSize: 11,
              fontFamily: Brand.fontFamily,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleColourPicker extends StatefulWidget {
  const _SimpleColourPicker({required this.initial});

  final Color initial;

  @override
  State<_SimpleColourPicker> createState() => _SimpleColourPickerState();
}

class _SimpleColourPickerState extends State<_SimpleColourPicker> {
  late Color _colour;

  @override
  void initState() {
    super.initState();
    _colour = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.appearanceColourPickerTitle),
      content: SingleChildScrollView(
        child: HsvColourPicker(
          color: _colour,
          onChanged: (c) => setState(() => _colour = c),
        ),
      ),
      actions: [
        LaunchPadButton.secondary(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        LaunchPadButton.primary(
          onPressed: () => Navigator.pop(context, _colour),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ColourRow extends StatelessWidget {
  const _ColourRow({
    required this.label,
    required this.colour,
    required this.onChanged,
  });

  final String label;
  final Color colour;
  final Future<void> Function(Color) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Material(
          color: colour,
          borderRadius: BorderRadius.circular(Brand.radius),
          child: InkWell(
            onTap: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (context) => _SimpleColourPicker(initial: colour),
              );
              if (picked != null) await onChanged(picked);
            },
            borderRadius: BorderRadius.circular(Brand.radius),
            child: const SizedBox(width: 40, height: 28),
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.suffix = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final Future<void> Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: 180,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: (v) => onChanged(v),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text('${value.round()}$suffix'),
        ),
      ],
    );
  }
}
