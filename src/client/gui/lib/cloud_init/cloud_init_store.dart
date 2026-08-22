import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

const cloudInitNamePattern = r'^[A-Za-z0-9._-]+$';
const defaultCloudInitTemplate = '#cloud-config\n';

class CloudInitConfigInfo {
  final String name;
  final DateTime modified;

  const CloudInitConfigInfo({
    required this.name,
    required this.modified,
  });
}

class CloudInitStore {
  CloudInitStore(this._directory);

  final Directory _directory;

  static Future<CloudInitStore> open() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/cloud-init');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return CloudInitStore(directory);
  }

  Directory get directory => _directory;

  static bool isValidName(String name) =>
      RegExp(cloudInitNamePattern).hasMatch(name);

  File _fileFor(String name) => File('${_directory.path}/$name.yaml');

  Future<List<CloudInitConfigInfo>> list() async {
    if (!await _directory.exists()) return [];

    final configs = <CloudInitConfigInfo>[];
    await for (final entity in _directory.list()) {
      if (entity is! File) continue;
      final fileName = entity.uri.pathSegments.last;
      if (!fileName.endsWith('.yaml')) continue;
      final name = fileName.substring(0, fileName.length - '.yaml'.length);
      if (!isValidName(name)) continue;
      final stat = await entity.stat();
      configs.add(CloudInitConfigInfo(name: name, modified: stat.modified));
    }
    configs.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return configs;
  }

  Future<String> read(String name) async {
    _ensureValidName(name);
    final file = _fileFor(name);
    if (!await file.exists()) {
      throw StateError('Cloud-init config "$name" does not exist');
    }
    return file.readAsString();
  }

  Future<void> write(String name, String contents) async {
    _ensureValidName(name);
    validateYaml(contents);
    await _fileFor(name).writeAsString(contents);
  }

  Future<void> rename(String from, String to) async {
    _ensureValidName(from);
    _ensureValidName(to);
    if (from == to) return;

    final source = _fileFor(from);
    final target = _fileFor(to);
    if (!await source.exists()) {
      throw StateError('Cloud-init config "$from" does not exist');
    }
    if (await target.exists()) {
      throw StateError('Cloud-init config "$to" already exists');
    }
    await source.rename(target.path);
  }

  Future<void> delete(String name) async {
    _ensureValidName(name);
    final file = _fileFor(name);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> importFile(String sourcePath, String name) async {
    _ensureValidName(name);
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('File does not exist: $sourcePath');
    }
    await write(name, await source.readAsString());
  }

  static void validateYaml(String contents) {
    try {
      loadYaml(contents);
    } on YamlException catch (error) {
      throw FormatException(error.message);
    }
  }

  void _ensureValidName(String name) {
    if (!isValidName(name)) {
      throw FormatException(
        'Invalid cloud-init name "$name". Use letters, digits, ".", "_" or "-".',
      );
    }
  }
}

final cloudInitStoreProvider = FutureProvider<CloudInitStore>((ref) {
  return CloudInitStore.open();
});

final cloudInitConfigsProvider =
    FutureProvider.autoDispose<List<CloudInitConfigInfo>>((ref) async {
  final store = await ref.watch(cloudInitStoreProvider.future);
  return store.list();
});

final cloudInitContentProvider =
    FutureProvider.autoDispose.family<String, String>((ref, name) async {
  final store = await ref.watch(cloudInitStoreProvider.future);
  return store.read(name);
});
