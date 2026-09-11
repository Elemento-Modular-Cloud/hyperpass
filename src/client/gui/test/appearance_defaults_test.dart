import 'package:elp_gui/appearance_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fresh AppearanceSettings uses the packed shuttle wallpaper', () {
    const settings = AppearanceSettings();
    expect(settings.wallpaperType, WallpaperType.image);
    expect(settings.wallpaper, kDefaultWallpaperAsset);
    expect(isBundledWallpaper(settings.wallpaper), isTrue);
    expect(wallpaperImageProvider(settings), isA<AssetImage>());
  });

  test('existing JSON still wins over packed defaults', () {
    final settings = AppearanceSettings.fromJson({
      'wallpaperType': 'atomosphere',
      'theme': 'dark',
    });
    expect(settings.wallpaperType, WallpaperType.atmosphere);
    expect(settings.theme, AppearanceTheme.dark);
  });
}
