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

const _maxLevelDbScanBytes = 8 * 1024 * 1024;
const _jsonWindowBytes = 8 * 1024;

const _asciiWallpaperType = <int>[
  0x22, 0x77, 0x61, 0x6c, 0x6c, 0x70, 0x61, 0x70, 0x65, 0x72,
  0x54, 0x79, 0x70, 0x65, 0x22,
];

final _utf16LeWallpaperType = [
  for (final b in _asciiWallpaperType) ...[b, 0x00],
];

String? _cachedLevelDbFingerprint;
ElectrosAppearanceSnapshot? _cachedLevelDbSnapshot;

class _LevelDbFile {
  _LevelDbFile(this.file, this.modified, this.size);
  final File file;
  final DateTime modified;
  final int size;
}

List<_LevelDbFile> _listLevelDbFiles() {
  final files = <_LevelDbFile>[];
  for (final dirPath in electrosLocalStorageDirs()) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.log') && !name.endsWith('.ldb')) continue;
      final stat = entity.statSync();
      files.add(_LevelDbFile(entity, stat.modified, stat.size));
    }
  }
  return files;
}

String _levelDbFingerprint(List<_LevelDbFile> files) {
  final parts = [
    for (final f in files)
      '${f.file.path}:${f.modified.millisecondsSinceEpoch}:${f.size}',
  ]..sort();
  return parts.join('|');
}

/// Newest mtime among Electros Local Storage leveldb files.
DateTime? electrosLocalStorageModified() {
  DateTime? newest;
  for (final file in _listLevelDbFiles()) {
    if (newest == null || file.modified.isAfter(newest)) {
      newest = file.modified;
    }
  }
  return newest;
}

/// Reads Electros `AppearanceHandler` JSON from Chromium/Electron Local Storage.
ElectrosAppearanceSnapshot? readElectrosAppearanceFromLocalStorage() {
  final files = _listLevelDbFiles();
  final fingerprint = _levelDbFingerprint(files);
  if (fingerprint == _cachedLevelDbFingerprint) {
    return _cachedLevelDbSnapshot;
  }

  AppearanceSettingsJson? best;
  var bestScore = -1;
  DateTime? bestModified;

  files.sort((a, b) => b.modified.compareTo(a.modified));
  for (final file in files) {
    if (file.size <= 0 || file.size > _maxLevelDbScanBytes) continue;
    final found = scanLevelDbAppearanceBytes(file.file.readAsBytesSync());
    final ageScore = file.modified.millisecondsSinceEpoch ~/ 1000000;
    for (final json in found) {
      final score = json.keys.length * 10 +
          (json['wallpaper'] != null ? 5 : 0) +
          (json['cardColour'] != null ? 3 : 0) +
          ageScore;
      if (score >= bestScore) {
        bestScore = score;
        best = json;
        bestModified = file.modified;
      }
    }
  }

  final snapshot = best == null
      ? null
      : ElectrosAppearanceSnapshot(
          json: best,
          modified: bestModified ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
  _cachedLevelDbFingerprint = fingerprint;
  _cachedLevelDbSnapshot = snapshot;
  return snapshot;
}

/// Finds non-nested `{"wallpaperType":...}` records in LevelDB bytes.
List<AppearanceSettingsJson> scanLevelDbAppearanceBytes(List<int> bytes) {
  final results = <AppearanceSettingsJson>[];
  _collectAppearanceJson(bytes, _asciiWallpaperType, 1, results);
  _collectAppearanceJson(bytes, _utf16LeWallpaperType, 2, results);
  return results;
}

void _collectAppearanceJson(
  List<int> bytes,
  List<int> needle,
  int stride,
  List<AppearanceSettingsJson> results,
) {
  var start = 0;
  while (true) {
    final hit = _indexOfBytes(bytes, needle, start);
    if (hit < 0) break;
    final window = _jsonWindow(bytes, hit, stride);
    if (window != null) {
      try {
        final text = stride == 2
            ? _decodeUtf16Le(window)
            : utf8.decode(window, allowMalformed: true);
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic> &&
            decoded.containsKey('wallpaperType')) {
          results.add(decoded);
        }
      } catch (_) {
        // Ignore truncated LevelDB fragments.
      }
    }
    start = hit + needle.length;
  }
}

int _indexOfBytes(List<int> haystack, List<int> needle, int start) {
  if (needle.isEmpty || start > haystack.length - needle.length) return -1;
  final first = needle[0];
  final lastIndex = haystack.length - needle.length;
  for (var i = start; i <= lastIndex; i++) {
    if (haystack[i] != first) continue;
    var matched = true;
    for (var j = 1; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return i;
  }
  return -1;
}

List<int>? _jsonWindow(List<int> bytes, int needleAt, int stride) {
  final open = stride == 2 ? const [0x7b, 0x00] : const [0x7b];
  final close = stride == 2 ? const [0x7d, 0x00] : const [0x7d];
  final minStart = needleAt > _jsonWindowBytes ? needleAt - _jsonWindowBytes : 0;

  var openAt = -1;
  for (var i = needleAt; i >= minStart; i -= stride) {
    if (_bytesEqualAt(bytes, i, close)) return null;
    if (_bytesEqualAt(bytes, i, open)) {
      openAt = i;
      break;
    }
  }
  if (openAt < 0) return null;

  final maxEnd = (openAt + _jsonWindowBytes).clamp(0, bytes.length);
  for (var i = needleAt; i < maxEnd; i += stride) {
    if (_bytesEqualAt(bytes, i, open) && i != openAt) return null;
    if (_bytesEqualAt(bytes, i, close)) {
      return bytes.sublist(openAt, i + stride);
    }
  }
  return null;
}

bool _bytesEqualAt(List<int> haystack, int index, List<int> needle) {
  if (index < 0 || index + needle.length > haystack.length) return false;
  for (var i = 0; i < needle.length; i++) {
    if (haystack[index + i] != needle[i]) return false;
  }
  return true;
}

String _decodeUtf16Le(List<int> bytes) {
  final codeUnits = List<int>.filled(bytes.length ~/ 2, 0);
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    codeUnits[i >> 1] = bytes[i] | (bytes[i + 1] << 8);
  }
  return String.fromCharCodes(codeUnits);
}
