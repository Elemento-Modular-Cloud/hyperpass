import 'dart:convert';
import 'dart:io';

/// Shared Elemento home used by Electros (`~/.elemento`).
Directory elementoHomeDirectory() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) {
    throw StateError('Unable to resolve home directory for ~/.elemento');
  }
  return Directory('$home${Platform.pathSeparator}.elemento');
}

Directory elementoBackgroundsDirectory() =>
    Directory('${elementoHomeDirectory().path}${Platform.pathSeparator}backgrounds');

File elementoAppearanceFile() =>
    File('${elementoHomeDirectory().path}${Platform.pathSeparator}appearance');

String elementoDisplayPath(String absolutePath) {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (home != null && absolutePath.startsWith(home)) {
    return '~${absolutePath.substring(home.length)}';
  }
  return absolutePath;
}

/// Turns Electros `file://` wallpaper URLs into filesystem paths.
String? normalizeWallpaperPath(String? raw) {
  if (raw == null || raw.isEmpty) return raw;
  if (raw.startsWith('file://')) {
    try {
      return Uri.parse(raw).toFilePath();
    } catch (_) {
      final stripped = raw.replaceFirst(RegExp(r'^file://'), '');
      return Uri.decodeFull(stripped);
    }
  }
  return raw;
}

typedef AppearanceSettingsJson = Map<String, dynamic>;

class ElectrosAppearanceSnapshot {
  const ElectrosAppearanceSnapshot({
    required this.json,
    required this.modified,
  });

  final AppearanceSettingsJson json;
  final DateTime modified;
}

List<String> electrosLocalStorageDirs() {
  final home = Platform.environment['HOME'];
  final appData = Platform.environment['APPDATA'];
  return [
    if (Platform.isMacOS && home != null) ...[
      '$home/Library/Application Support/electros/Local Storage/leveldb',
      '$home/Library/Application Support/electros/Default/Local Storage/leveldb',
      '$home/Library/Application Support/elemento-client-gui/Local Storage/leveldb',
    ],
    if (Platform.isLinux && home != null) ...[
      '$home/.config/electros/Local Storage/leveldb',
      '$home/.config/Electros/Local Storage/leveldb',
    ],
    if (Platform.isWindows && appData != null) ...[
      '$appData\\electros\\Local Storage\\leveldb',
      '$appData\\Electros\\Local Storage\\leveldb',
    ],
  ];
}

/// Newest mtime among Electros Local Storage leveldb files.
DateTime? electrosLocalStorageModified() {
  DateTime? newest;
  for (final dirPath in electrosLocalStorageDirs()) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.log') && !name.endsWith('.ldb')) continue;
      final modified = entity.statSync().modified;
      if (newest == null || modified.isAfter(newest)) {
        newest = modified;
      }
    }
  }
  return newest;
}

/// Reads Electros `AppearanceHandler` JSON from Chromium/Electron Local Storage.
ElectrosAppearanceSnapshot? readElectrosAppearanceFromLocalStorage() {
  AppearanceSettingsJson? best;
  var bestScore = -1;
  DateTime? bestModified;

  for (final dirPath in electrosLocalStorageDirs()) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.uri.pathSegments.last;
          return name.endsWith('.log') || name.endsWith('.ldb');
        })
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    for (final file in files) {
      final found = _scanLevelDbFile(file);
      for (final entry in found) {
        if (entry.score >= bestScore) {
          bestScore = entry.score;
          best = entry.json;
          bestModified = file.statSync().modified;
        }
      }
    }
  }

  if (best == null) return null;
  return ElectrosAppearanceSnapshot(
    json: best,
    modified: bestModified ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class _ScannedAppearance {
  _ScannedAppearance(this.json, this.score);
  final AppearanceSettingsJson json;
  final int score;
}

List<_ScannedAppearance> _scanLevelDbFile(File file) {
  final bytes = file.readAsBytesSync();
  final texts = <String>[
    utf8.decode(bytes, allowMalformed: true),
    _decodeUtf16Le(bytes),
  ];

  final results = <_ScannedAppearance>[];
  final pattern = RegExp(r'\{[^{}]*"wallpaperType"[^{}]*\}');
  for (final text in texts) {
    for (final match in pattern.allMatches(text)) {
      try {
        final json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
        if (!json.containsKey('wallpaperType')) continue;
        // Prefer more complete records (cardColour, wallpaper path, etc.).
        final score = json.keys.length * 10 +
            (json['wallpaper'] != null ? 5 : 0) +
            (json['cardColour'] != null ? 3 : 0) +
            file.statSync().modified.millisecondsSinceEpoch ~/ 1000000;
        results.add(_ScannedAppearance(json, score));
      } catch (_) {
        // Ignore truncated LevelDB fragments.
      }
    }
  }
  return results;
}

String _decodeUtf16Le(List<int> bytes) {
  final codeUnits = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(codeUnits);
}
