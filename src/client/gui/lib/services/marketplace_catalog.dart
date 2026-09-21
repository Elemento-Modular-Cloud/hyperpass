import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../auth/spacedock_config.dart';

/// Repo that owns the live `services/` tree (local checkouts / seed metadata).
const marketplaceRepoOwner = 'Elemento-Modular-Cloud';
const marketplaceRepoName = 'elemento-marketplace';
const marketplaceRepoUrl =
    'https://github.com/$marketplaceRepoOwner/$marketplaceRepoName.git';

/// Optional direct JSON bundle URL (`ELP_MARKETPLACE_URL`).
///
/// Used only when [marketplaceDirOverride] is unset. Production fetches the
/// schema-1 bundle from Spacedock when signed in.
String? marketplaceBundleUrlOverride() =>
    Platform.environment['ELP_MARKETPLACE_URL'];

/// Clone root or `services/` tree (`ELP_MARKETPLACE_DIR`).
///
/// A checkout looks like the elemento-marketplace repo (`services/<id>/…`).
/// The same layout is what a gated CDN drop will contain in production.
String? marketplaceDirOverride() => Platform.environment['ELP_MARKETPLACE_DIR'];

/// Resolves [path] to the `services/` directory of a marketplace checkout.
///
/// Accepts either the repo root (`…/elemento-marketplace`) or the `services/`
/// folder itself.
Directory? resolveMarketplaceServicesDir(String? path) {
  if (path == null || path.isEmpty) return null;
  final root = Directory(path);
  final nested = Directory(
    '${root.path}${Platform.pathSeparator}services',
  );
  if (nested.existsSync()) return nested;
  return root;
}

/// Skip editor droppings and git internals when watching a checkout.
bool ignoreMarketplaceWatchPath(String path) {
  final normalised = path.replaceAll('\\', '/');
  if (normalised.contains('/.git/')) return true;
  final base = normalised.split('/').last;
  return base == '.DS_Store' ||
      base == 'Thumbs.db' ||
      base.endsWith('~') ||
      base.endsWith('.swp');
}

/// How long to wait after a burst of filesystem events before reloading.
const marketplaceWatchDebounce = Duration(milliseconds: 400);

/// HEAD of a git checkout at [path], or of its parent when [path] is
/// `services/`. `local` when git is unavailable.
Future<String> marketplaceCheckoutCommit(String path) async {
  for (final candidate in [path, Directory(path).parent.path]) {
    try {
      final result = await Process.run(
        'git',
        ['-C', candidate, 'rev-parse', 'HEAD'],
      );
      if (result.exitCode == 0) {
        final sha = (result.stdout as String).trim();
        if (sha.isNotEmpty) return sha;
      }
    } on ProcessException {
      // No git in PATH — treat as an unsigned drop (CDN / unpacked tree).
    }
  }
  return 'local';
}

/// GitHub token for a GitHub-hosted `ELP_MARKETPLACE_URL` override.
String? marketplaceGithubToken() =>
    Platform.environment['ELP_MARKETPLACE_TOKEN'] ??
    Platform.environment['GITHUB_TOKEN'];

const _cacheFileName = 'marketplace_services.json';
const _excludedNames = {'.DS_Store', 'Thumbs.db'};

/// Fetches the marketplace service library JSON: remote (or local dir) → disk
/// cache. Returns null when there is no directory, cache, or reachable bundle.
class MarketplaceCatalog {
  MarketplaceCatalog({
    http.Client? httpClient,
    Directory? cacheDirectory,
    String? bundleUrl,
    String? servicesDirectory,
    String? githubToken,
    String? accessToken,
    Future<String?> Function()? accessTokenProvider,
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _cacheDirectory = cacheDirectory,
        bundleUrl = bundleUrl ?? marketplaceBundleUrlOverride(),
        servicesDirectory = servicesDirectory ?? marketplaceDirOverride(),
        githubToken = githubToken ?? marketplaceGithubToken(),
        accessToken = accessToken,
        accessTokenProvider = accessTokenProvider;

  final http.Client _client;
  final bool _ownsClient;
  final Directory? _cacheDirectory;

  /// Direct JSON bundle URL. Empty/null means Spacedock (when signed in).
  final String? bundleUrl;

  /// Clone root or `services/` tree. When set, the catalog reads that
  /// directory on every load (no remote JSON URL).
  final String? servicesDirectory;

  final String? githubToken;
  final String? accessToken;
  final Future<String?> Function()? accessTokenProvider;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// Returns bundle JSON, or null when there is nothing to load.
  Future<String?> loadJson({bool forceRefresh = false}) async {
    if (servicesDirectory != null && servicesDirectory!.isNotEmpty) {
      return _loadFromServicesDirectory();
    }

    final cacheFile = await _cacheFile();
    if (!forceRefresh && await cacheFile.exists()) {
      try {
        final cached = await cacheFile.readAsString();
        final refreshed = await _tryRefresh(cacheFile);
        return refreshed ?? cached;
      } catch (_) {
        // Corrupt cache — fall through to a full reload.
      }
    }

    final remote = await _tryRefresh(cacheFile);
    if (remote != null) return remote;

    if (await cacheFile.exists()) {
      try {
        return await cacheFile.readAsString();
      } catch (_) {}
    }

    return null;
  }

  Future<String?> _loadFromServicesDirectory() async {
    final path = servicesDirectory;
    if (path == null || path.isEmpty) return null;
    final servicesDir = resolveMarketplaceServicesDir(path);
    if (servicesDir == null || !await servicesDir.exists()) {
      throw StateError('ELP_MARKETPLACE_DIR does not exist: $path');
    }
    final bundle = await buildBundleFromServicesDir(
      servicesDir,
      commit: await marketplaceCheckoutCommit(path),
      repo: marketplaceRepoUrl,
    );
    return serialiseBundle(bundle);
  }

  Future<String?> _tryRefresh(File cacheFile) async {
    try {
      final token = await _resolveAccessToken();
      final url = _remoteBundleUrl(token);
      if (url == null) return null;
      final json = await _fetchJsonBundle(url, accessToken: token);
      await _writeCache(cacheFile, json);
      return json;
    } catch (_) {
      return null;
    }
  }

  String? _remoteBundleUrl(String? token) {
    if (bundleUrl != null && bundleUrl!.isNotEmpty) return bundleUrl;
    if (token != null && token.isNotEmpty) {
      return SpacedockConfig.marketplaceBundleUrl();
    }
    return null;
  }

  Future<String?> _resolveAccessToken() async {
    if (accessTokenProvider != null) {
      return accessTokenProvider!();
    }
    if (accessToken != null && accessToken!.isNotEmpty) return accessToken;
    return null;
  }

  Future<String> _fetchJsonBundle(String url, {String? accessToken}) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: _authHeaders(
        accept: 'application/json',
        url: url,
        accessToken: accessToken,
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Marketplace bundle HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    _assertBundleSchema(response.body);
    return response.body;
  }

  Map<String, String> _authHeaders({
    required String accept,
    required String url,
    String? accessToken,
  }) {
    final headers = <String, String>{
      'Accept': accept,
      'User-Agent': 'Electros-LaunchPad',
    };
    if (_isGithubUrl(url) &&
        githubToken != null &&
        githubToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $githubToken';
    } else if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    return headers;
  }

  bool _isGithubUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'github.com' || host.endsWith('.github.com');
  }

  Future<File> _cacheFile() async {
    final directory = _cacheDirectory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/marketplace',
        );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/$_cacheFileName');
  }

  Future<void> _writeCache(File file, String json) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }
}

/// Flatten a local `services/` directory into the on-disk bundle schema.
Future<Map<String, Object?>> buildBundleFromServicesDir(
  Directory servicesDir, {
  required String commit,
  required String repo,
}) async {
  final services = <Map<String, Object?>>[];
  final entries = servicesDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final serviceDir in entries) {
    final id = serviceDir.path
        .split(Platform.pathSeparator)
        .where((p) => p.isNotEmpty)
        .last;
    final manifest =
        File('${serviceDir.path}${Platform.pathSeparator}service.yaml');
    if (!await manifest.exists()) continue;
    services.add({
      'id': id,
      'files': await _collectServiceFiles(serviceDir),
    });
  }

  if (services.isEmpty) {
    throw StateError(
      'No services with a service.yaml found in ${servicesDir.path}',
    );
  }

  return {
    'schema': 1,
    'source': {'repo': repo, 'commit': commit},
    'services': services,
  };
}

/// Flatten a GitHub zipball into the on-disk bundle schema.
Map<String, Object?> buildBundleFromZipArchive(
  Archive archive, {
  required String commit,
  required String repo,
}) {
  // Paths look like `Elemento-Modular-Cloud-elemento-marketplace-<sha>/services/<id>/…`
  final byService = <String, Map<String, String>>{};

  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name.replaceAll('\\', '/');
    final parts = name.split('/');
    final servicesIdx = parts.indexOf('services');
    if (servicesIdx < 0 || servicesIdx + 1 >= parts.length) continue;

    final serviceId = parts[servicesIdx + 1];
    if (serviceId.isEmpty) continue;
    final relativeParts = parts.sublist(servicesIdx + 2);
    if (relativeParts.isEmpty) continue;
    final relative = relativeParts.join('/');
    if (relative.isEmpty) continue;
    final baseName = relativeParts.last;
    if (_excludedNames.contains(baseName)) continue;

    final content = entry.readBytes();
    if (content == null) continue;
    final text = _decodeText(content);
    if (text == null) continue;
    byService.putIfAbsent(serviceId, () => <String, String>{})[relative] = text;
  }

  final services = <Map<String, Object?>>[];
  final ids = byService.keys.toList()..sort();
  for (final id in ids) {
    final files = byService[id]!;
    if (!files.containsKey('service.yaml')) continue;
    services.add({'id': id, 'files': files});
  }

  if (services.isEmpty) {
    throw StateError('Marketplace zipball contained no service.yaml files');
  }

  return {
    'schema': 1,
    'source': {'repo': repo, 'commit': commit},
    'services': services,
  };
}

String serialiseBundle(Map<String, Object?> bundle) =>
    '${const JsonEncoder.withIndent('  ').convert(bundle)}\n';

void _assertBundleSchema(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map ||
      decoded['schema'] != 1 ||
      decoded['services'] is! List) {
    throw const FormatException('Unsupported marketplace bundle schema');
  }
}

Future<Map<String, String>> _collectServiceFiles(Directory serviceDir) async {
  final files = <String, String>{};
  await for (final entity
      in serviceDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (_excludedNames.contains(entity.uri.pathSegments.last)) continue;
    final relative = entity.path
        .substring(serviceDir.path.length)
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/'), '');
    try {
      files[relative] = await entity.readAsString();
    } on FileSystemException {
      // Skip binaries / unreadable files, matching the Python bundler.
    }
  }
  return files;
}

String? _decodeText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}
