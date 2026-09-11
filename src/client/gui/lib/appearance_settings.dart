import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background_providers.dart';
import 'brand.dart';
import 'downloads/download_manager.dart';
import 'elemento_paths.dart';
import 'providers.dart';
import 'wallpaper_store.dart';

/// Packed first-run wallpaper (space shuttle launch).
const kDefaultWallpaperAsset = 'assets/backgrounds/spaceshuttle_launch.jpg';

/// Electros `AppearanceHandler.wallpaperType` (note: `atomosphere` typo preserved).
enum WallpaperType {
  atmosphere,
  image,
  provider,
  colour,
  none,
}

/// Electros `AppearanceTheme` / `ThemeClass`.
enum AppearanceTheme {
  light,
  dark,
  highContrast,
}

/// Mirrors Electros `AppearanceSettings` in `AppearanceHandler.ts`.
@immutable
class AppearanceSettings {
  const AppearanceSettings({
    this.wallpaperType = WallpaperType.image,
    this.wallpaper = kDefaultWallpaperAsset,
    this.wallpaperBrightness = 100,
    this.wallpaperBlur = 0,
    this.useGlassmorphism = true,
    this.theme = AppearanceTheme.light,
    this.wasThemeAutoSelected = true,
    this.cardOpacity = 28,
    this.cardColour,
    this.animate = true,
  });

  final WallpaperType wallpaperType;
  final String? wallpaper;
  final double wallpaperBrightness;
  final double wallpaperBlur;
  final bool useGlassmorphism;
  final AppearanceTheme theme;
  final bool wasThemeAutoSelected;
  final double cardOpacity;
  final String? cardColour;
  final bool animate;

  Color? get wallpaperColor {
    if (wallpaperType != WallpaperType.colour || wallpaper == null) return null;
    return _colorFromHex(wallpaper!);
  }

  Color get cardColorValue =>
      _colorFromHex(cardColour ?? defaultCardColourHex(theme)) ??
      Colors.white;

  Brightness get brightness => switch (theme) {
        AppearanceTheme.light => Brightness.light,
        AppearanceTheme.dark || AppearanceTheme.highContrast => Brightness.dark,
      };

  AppearanceSettings copyWith({
    WallpaperType? wallpaperType,
    String? wallpaper,
    bool clearWallpaper = false,
    double? wallpaperBrightness,
    double? wallpaperBlur,
    bool? useGlassmorphism,
    AppearanceTheme? theme,
    bool? wasThemeAutoSelected,
    double? cardOpacity,
    String? cardColour,
    bool? animate,
  }) {
    return AppearanceSettings(
      wallpaperType: wallpaperType ?? this.wallpaperType,
      wallpaper: clearWallpaper ? null : (wallpaper ?? this.wallpaper),
      wallpaperBrightness: wallpaperBrightness ?? this.wallpaperBrightness,
      wallpaperBlur: wallpaperBlur ?? this.wallpaperBlur,
      useGlassmorphism: useGlassmorphism ?? this.useGlassmorphism,
      theme: theme ?? this.theme,
      wasThemeAutoSelected:
          wasThemeAutoSelected ?? this.wasThemeAutoSelected,
      cardOpacity: cardOpacity ?? this.cardOpacity,
      cardColour: cardColour ?? this.cardColour,
      animate: animate ?? this.animate,
    );
  }

  Map<String, dynamic> toJson() => {
        'wallpaperType': switch (wallpaperType) {
          WallpaperType.atmosphere => 'atomosphere',
          WallpaperType.colour => 'colour',
          _ => wallpaperType.name,
        },
        if (wallpaper != null) 'wallpaper': wallpaper,
        'wallpaperBrightness': wallpaperBrightness.round(),
        'wallpaperBlur': wallpaperBlur.round(),
        'useGlassmorphism': useGlassmorphism,
        'theme': theme.name,
        'wasThemeAutoSelected': wasThemeAutoSelected,
        'cardOpacity': cardOpacity.round(),
        if (cardColour != null) 'cardColour': cardColour,
        'animate': animate,
      };

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) {
    final typeRaw = json['wallpaperType'] as String? ?? 'atomosphere';
    final wallpaperType = switch (typeRaw) {
      'atomosphere' || 'atmosphere' => WallpaperType.atmosphere,
      'image' => WallpaperType.image,
      'provider' => WallpaperType.provider,
      'colour' || 'color' => WallpaperType.colour,
      'none' => WallpaperType.none,
      _ => WallpaperType.atmosphere,
    };

    final themeRaw = json['theme'] as String? ?? 'light';
    final theme = AppearanceTheme.values.firstWhere(
      (t) => t.name == themeRaw,
      orElse: () => AppearanceTheme.light,
    );

    return AppearanceSettings(
      wallpaperType: wallpaperType,
      wallpaper: normalizeWallpaperPath(json['wallpaper'] as String?),
      wallpaperBrightness:
          (json['wallpaperBrightness'] as num?)?.toDouble() ?? 100,
      wallpaperBlur: (json['wallpaperBlur'] as num?)?.toDouble() ?? 0,
      useGlassmorphism: json['useGlassmorphism'] as bool? ?? true,
      theme: theme,
      wasThemeAutoSelected: json['wasThemeAutoSelected'] as bool? ?? true,
      cardOpacity: (json['cardOpacity'] as num?)?.toDouble() ?? 28,
      cardColour: json['cardColour'] as String?,
      animate: json['animate'] as bool? ?? true,
    );
  }

  static String defaultCardColourHex(AppearanceTheme theme) =>
      switch (theme) {
        AppearanceTheme.light => '#ffffff',
        AppearanceTheme.dark => '#505050',
        AppearanceTheme.highContrast => '#282828',
      };
}

const appearanceStorageKey = 'appearance';

Color? _colorFromHex(String hex) {
  var value = hex.replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final intVal = int.tryParse(value, radix: 16);
  if (intVal == null) return null;
  return Color(intVal);
}

String colorToHex(Color color, {bool withHash = true}) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  final hex = rgb.toRadixString(16).padLeft(6, '0');
  return withHash ? '#$hex' : hex;
}

Color colorWithOpacity(Color color, double opacityPercent) {
  return color.withValues(alpha: renderOpacityAlpha(opacityPercent));
}

/// Electros `getAppropriateThemeForColour`.
AppearanceTheme themeForBackgroundColour(Color colour) {
  final r = colour.r;
  final g = colour.g;
  final b = colour.b;
  final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
  if (luminance > 0.50) return AppearanceTheme.light;
  if (luminance > 0.25) return AppearanceTheme.dark;
  return AppearanceTheme.highContrast;
}

AppearanceSettings? _tryParseAppearance(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return AppearanceSettings.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  } catch (_) {
    return null;
  }
}

void _mirrorAppearanceToElemento(AppearanceSettings settings) {
  try {
    final home = elementoHomeDirectory();
    if (!home.existsSync()) {
      home.createSync(recursive: true);
    }
    elementoAppearanceFile().writeAsStringSync(jsonEncode(settings.toJson()));
  } catch (_) {}
}

/// Loads appearance preferring the newest of `~/.elemento/appearance` and Electros.
///
/// [includeElectrosLocalStorage] is expensive (Chromium LevelDB). Skip it on
/// the first frame and merge Electros afterwards.
AppearanceSettings loadAppearanceSettings({
  String? sharedPrefsRaw,
  bool includeElectrosLocalStorage = true,
}) {
  final file = elementoAppearanceFile();
  AppearanceSettings? fromFile;
  DateTime? fileModified;
  if (file.existsSync()) {
    fromFile = _tryParseAppearance(file.readAsStringSync());
    fileModified = file.statSync().modified;
  }

  ElectrosAppearanceSnapshot? electros;
  if (includeElectrosLocalStorage) {
    electros = readElectrosAppearanceFromLocalStorage();
  }
  AppearanceSettings? fromElectros;
  DateTime? electrosModified;
  if (electros != null) {
    fromElectros = AppearanceSettings.fromJson(electros.json);
    electrosModified = electros.modified;
  }

  // Prefer whichever Elemento source was updated more recently.
  if (fromElectros != null &&
      (fromFile == null ||
          fileModified == null ||
          electrosModified!.isAfter(fileModified))) {
    _mirrorAppearanceToElemento(fromElectros);
    return fromElectros;
  }
  if (fromFile != null) return fromFile;

  final fromPrefs = _tryParseAppearance(sharedPrefsRaw);
  if (fromPrefs != null) return fromPrefs;

  return const AppearanceSettings();
}

bool appearanceEquals(AppearanceSettings a, AppearanceSettings b) =>
    jsonEncode(a.toJson()) == jsonEncode(b.toJson());

class AppearanceSettingsNotifier extends Notifier<AppearanceSettings> {
  static const _pollInterval = Duration(seconds: 2);

  @override
  AppearanceSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final initial = loadAppearanceSettings(
      sharedPrefsRaw: prefs.getString(appearanceStorageKey),
      includeElectrosLocalStorage: false,
    );

    _startElementoWatchers();
    Future<void>.microtask(() {
      if (ref.mounted) _reloadFromElemento();
    });
    return initial;
  }

  void _startElementoWatchers() {
    StreamSubscription<FileSystemEvent>? fileWatch;
    Timer? poll;

    ref.onDispose(() {
      fileWatch?.cancel();
      poll?.cancel();
    });

    try {
      final home = elementoHomeDirectory();
      if (!home.existsSync()) {
        home.createSync(recursive: true);
      }
      fileWatch = home.watch(events: FileSystemEvent.all).listen((event) {
        final name = event.path.split(Platform.pathSeparator).last;
        if (name == 'appearance' || name == 'backgrounds') {
          _reloadFromElemento();
        }
      });
    } catch (_) {}

    poll = Timer.periodic(_pollInterval, (_) => _reloadFromElemento());
  }

  void _reloadFromElemento() {
    final prefs = ref.read(sharedPreferencesProvider);
    final next = loadAppearanceSettings(
      sharedPrefsRaw: prefs.getString(appearanceStorageKey),
    );
    if (!appearanceEquals(next, state)) {
      state = next;
      // Keep SharedPreferences in sync without rewriting Elemento (already newest).
      prefs.setString(appearanceStorageKey, jsonEncode(next.toJson()));
    }
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(state.toJson());
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(appearanceStorageKey, encoded);

    try {
      final home = elementoHomeDirectory();
      if (!await home.exists()) {
        await home.create(recursive: true);
      }
      await elementoAppearanceFile().writeAsString(encoded);
    } catch (_) {
      // SharedPreferences remains the local fallback if ~/.elemento is unwritable.
    }
  }

  Future<void> update(AppearanceSettings next) async {
    state = next;
    await _persist();
  }

  Future<void> setWallpaperType(WallpaperType type) async {
    await update(state.copyWith(wallpaperType: type));
  }

  Future<void> setColourWallpaper(Color colour) async {
    final hex = colorToHex(colour);
    var next = state.copyWith(
      wallpaperType: WallpaperType.colour,
      wallpaper: hex,
    );
    if (state.wasThemeAutoSelected) {
      next = next.copyWith(theme: themeForBackgroundColour(colour));
    }
    await update(next);
  }

  Future<void> setImageWallpaper(String path) async {
    await update(state.copyWith(
      wallpaperType: WallpaperType.image,
      wallpaper: normalizeWallpaperPath(path),
    ));
  }

  Future<void> setDefaultWallpaper() async {
    await update(state.copyWith(
      wallpaperType: WallpaperType.image,
      wallpaper: kDefaultWallpaperAsset,
    ));
  }

  Future<void> importImageWallpaper(String sourcePath) async {
    final store = await WallpaperStore.open();
    final file = await store.importFrom(sourcePath);
    await setImageWallpaper(file.path);
  }

  Future<void> setProviderWallpaper(String providerReference) async {
    await update(state.copyWith(
      wallpaperType: WallpaperType.provider,
      wallpaper: providerReference,
    ));
  }

  Future<void> setNoneWallpaper() async {
    await update(state.copyWith(
      wallpaperType: WallpaperType.none,
      clearWallpaper: true,
      wallpaperBrightness: 100,
      wallpaperBlur: 0,
    ));
  }

  Future<void> setAtmosphereWallpaper({bool? animate}) async {
    await update(state.copyWith(
      wallpaperType: WallpaperType.atmosphere,
      clearWallpaper: true,
      animate: animate ?? state.animate,
    ));
  }

  Future<void> setUseGlassmorphism(bool value) async {
    await update(state.copyWith(useGlassmorphism: value));
  }

  Future<void> setTheme(AppearanceTheme theme, {bool autoSelected = false}) async {
    await update(state.copyWith(
      theme: theme,
      wasThemeAutoSelected: autoSelected,
    ));
  }

  Future<void> setCardColour(Color colour) async {
    var next = state.copyWith(cardColour: colorToHex(colour));
    if (!state.useGlassmorphism) {
      next = next.copyWith(
        theme: themeForBackgroundColour(colour),
        wasThemeAutoSelected: true,
      );
    }
    await update(next);
  }

  Future<void> setCardOpacity(double opacity) async {
    var next = state.copyWith(cardOpacity: opacity);
    if (!state.useGlassmorphism) {
      next = next.copyWith(
        theme: themeForBackgroundColour(state.cardColorValue),
        wasThemeAutoSelected: true,
      );
    }
    await update(next);
  }

  Future<void> setAnimateBackground(bool value) async {
    await update(state.copyWith(animate: value));
  }

  Future<void> setWallpaperBrightness(double value) async {
    if (!{WallpaperType.image, WallpaperType.provider}
        .contains(state.wallpaperType)) {
      return;
    }
    await update(state.copyWith(wallpaperBrightness: value));
  }

  Future<void> setWallpaperBlur(double value) async {
    if (!{WallpaperType.image, WallpaperType.provider}
        .contains(state.wallpaperType)) {
      return;
    }
    await update(state.copyWith(wallpaperBlur: value));
  }
}

final appearanceSettingsProvider =
    NotifierProvider<AppearanceSettingsNotifier, AppearanceSettings>(
  AppearanceSettingsNotifier.new,
);

/// Theme background colour when wallpaper is `none` (Electros `--background-color`).
Color themeBackgroundColor(AppearanceTheme theme) => switch (theme) {
      AppearanceTheme.light => const Color(0xFFF5F5FA),
      AppearanceTheme.dark => const Color(0xFF1A1C20),
      AppearanceTheme.highContrast => const Color(0xFF000000),
    };

bool isBundledWallpaper(String? path) {
  if (path == null || path.isEmpty) return false;
  return path == kDefaultWallpaperAsset || path.startsWith('assets/');
}

File? wallpaperImageFile(AppearanceSettings settings) {
  if (settings.wallpaperType != WallpaperType.image) {
    return null;
  }
  final path = normalizeWallpaperPath(settings.wallpaper);
  if (path == null || path.isEmpty || isBundledWallpaper(path)) return null;
  final file = File(path);
  return file.existsSync() ? file : null;
}

/// Image provider for [WallpaperType.image], including the packed default asset.
ImageProvider? wallpaperImageProvider(AppearanceSettings settings) {
  if (settings.wallpaperType != WallpaperType.image) return null;
  final path = normalizeWallpaperPath(settings.wallpaper);
  if (path == null || path.isEmpty || isBundledWallpaper(path)) {
    return const AssetImage(kDefaultWallpaperAsset);
  }
  final file = File(path);
  if (file.existsSync()) return FileImage(file);
  return null;
}

/// Resolves a POTD/network wallpaper URL for [WallpaperType.provider].
final providerWallpaperUrlProvider = FutureProvider<String?>((ref) async {
  final settings = ref.watch(appearanceSettingsProvider);
  if (settings.wallpaperType != WallpaperType.provider) return null;

  final raw = settings.wallpaper;
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

  final image = await BackgroundProviderService.fetchLatest(raw);
  return image?.imgUrl;
});

/// Downloads the current POTD image through the shared download manager.
final providerWallpaperFileProvider = FutureProvider<File?>((ref) async {
  final settings = ref.watch(appearanceSettingsProvider);
  if (settings.wallpaperType != WallpaperType.provider) return null;

  final url = await ref.watch(providerWallpaperUrlProvider.future);
  if (url == null || url.isEmpty) return null;

  final reference = settings.wallpaper ?? 'provider';
  final safeRef = reference.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final dest = File(
    '${elementoBackgroundsDirectory().path}${Platform.pathSeparator}potd-$safeRef.jpg',
  );
  if (dest.existsSync() && dest.lengthSync() > 0) return dest;

  await ref.read(downloadManagerProvider.notifier).enqueueAndWait(
        kind: DownloadKind.potd,
        label: 'Wallpaper ($reference)',
        dedupKey: 'potd:$url',
        execute: (controller) async {
          await downloadUrlToFile(
            url,
            dest,
            onProgress: controller.setPercent,
            isCancelled: () => controller.isCancelled,
          );
          if (!controller.isCancelled) controller.setPath(dest.path);
        },
      );
  return dest.existsSync() ? dest : null;
});
