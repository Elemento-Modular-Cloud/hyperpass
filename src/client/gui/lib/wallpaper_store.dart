import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'elemento_paths.dart';

const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};

/// Electros wallpaper library under `~/.elemento/backgrounds`.
class WallpaperStore {
  WallpaperStore(this._directory);

  final Directory _directory;

  static Future<WallpaperStore> open() async {
    final directory = elementoBackgroundsDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return WallpaperStore(directory);
  }

  Directory get directory => _directory;

  String get displayPath => elementoDisplayPath(_directory.path);

  Future<List<File>> list() async {
    if (!await _directory.exists()) return [];

    final files = <File>[];
    await for (final entity in _directory.list()) {
      if (entity is! File) continue;
      if (_imageExtensions.contains(_extension(entity.path))) {
        files.add(entity);
      }
    }
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  Future<File> importFrom(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('File does not exist: $sourcePath');
    }

    final extension = _extension(sourcePath);
    if (!_imageExtensions.contains(extension)) {
      throw FormatException('Unsupported image type: $extension');
    }

    final baseName = _basenameWithoutExtension(sourcePath);
    final safeBase = baseName.replaceAll(RegExp(r'[^\w.-]'), '_');
    var targetName = '$safeBase$extension';
    var counter = 1;
    while (await File('${_directory.path}/$targetName').exists()) {
      targetName = '${safeBase}_$counter$extension';
      counter++;
    }

    final target = File('${_directory.path}/$targetName');
    await source.copy(target.path);
    return target;
  }

  Future<void> delete(String path) async {
    final file = File(path);
    if (!file.path.startsWith(_directory.path)) {
      throw StateError('Refusing to delete file outside wallpaper directory');
    }
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '';
    return path.substring(dot).toLowerCase();
  }

  static String _basenameWithoutExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot == -1) return name;
    return name.substring(0, dot);
  }
}

final wallpaperStoreProvider = FutureProvider<WallpaperStore>((ref) {
  return WallpaperStore.open();
});

final storedWallpapersProvider =
    FutureProvider.autoDispose<List<File>>((ref) async {
  final store = await ref.watch(wallpaperStoreProvider.future);
  return store.list();
});
