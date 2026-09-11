import 'dart:convert';

import 'package:elp_gui/elemento_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds ASCII appearance JSON inside LevelDB noise', () {
    final json = {
      'wallpaperType': 'image',
      'wallpaper': '/tmp/wall.jpg',
      'cardColour': '#0f1017',
    };
    final encoded = utf8.encode(jsonEncode(json));
    final bytes = <int>[
      ...List<int>.filled(32, 0x11),
      ...utf8.encode('noise{not-json}'),
      ...encoded,
      ...List<int>.filled(32, 0x22),
    ];

    expect(scanLevelDbAppearanceBytes(bytes), [json]);
  });

  test('finds UTF-16LE appearance JSON inside LevelDB noise', () {
    final json = {
      'wallpaperType': 'colour',
      'wallpaper': '#ffffff',
    };
    final encoded = utf8.encode(jsonEncode(json));
    final utf16 = <int>[
      for (final b in encoded) ...[b, 0x00],
    ];
    final bytes = <int>[
      ...List<int>.filled(16, 0xaa),
      ...utf16,
      ...List<int>.filled(16, 0xbb),
    ];

    expect(scanLevelDbAppearanceBytes(bytes), [json]);
  });

  test('ignores wallpaperType without a surrounding JSON object', () {
    expect(
      scanLevelDbAppearanceBytes(utf8.encode('"wallpaperType":"image"')),
      isEmpty,
    );
  });
}
