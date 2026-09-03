import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

const marketplaceBundleAsset = 'assets/marketplace_services.json';

/// Placeholder syntax used by the marketplace service library, e.g.
/// `{{qdrant_api_key}}`. Unsubstituted placeholders are intentional: the
/// services' own `configure-*.sh` scripts treat them as "generate me a value".
final _placeholderPattern = RegExp(r'\{\{([A-Za-z0-9_]+)\}\}');

/// `SOME_KEY=` at the start of a line. Placeholders live in the services' env
/// files, so the assignment target names the setting a placeholder fills.
final _assignmentPattern = RegExp(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=');

final _versionSuffixPattern = RegExp(r'_v(\d+)$');

/// Service id without its `_v<N>` suffix, so every version of a tool shares a
/// family, e.g. `n8n`, `n8n_v2` and `n8n_v3` are all `n8n`.
String serviceFamily(String serviceId) =>
    serviceId.replaceFirst(_versionSuffixPattern, '');

/// A `{{placeholder}}` a service accepts, discovered by scanning its files.
///
/// The manifests carry no parameter schema, so [key] and [documentation] are
/// recovered from how the placeholder is written in its source file.
class ServiceVariable {
  ServiceVariable({
    required this.name,
    required this.sources,
    this.key,
    this.documentation,
  });

  /// Placeholder name, i.e. `api_key` for `{{api_key}}`.
  final String name;

  /// Setting the placeholder fills, i.e. `QDRANT__SERVICE__API_KEY` for the
  /// line `QDRANT__SERVICE__API_KEY={{api_key}}`. Null when the placeholder is
  /// not a plain assignment.
  final String? key;

  /// Comment lines written directly above the placeholder, which the service
  /// authors use to explain the setting.
  final String? documentation;

  /// Relative paths within the service directory that use this placeholder.
  final List<String> sources;

  /// Best available human label: the setting name, else the placeholder.
  String get label => key ?? name;
}

/// Scans a service directory for placeholders, keeping the order they appear
/// in so grouped settings (all the `openai_*` keys, say) stay together.
List<ServiceVariable> _extractVariables(Map<String, String> sources) {
  final found = <String, ServiceVariable>{};

  for (final MapEntry(key: path, value: content) in sources.entries) {
    final comment = <String>[];

    for (final line in content.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#')) {
        final text = trimmed.substring(1).trim();
        // Skip shebangs and blank separator comments.
        if (text.isNotEmpty && !text.startsWith('!')) comment.add(text);
        continue;
      }

      final matches = _placeholderPattern.allMatches(line).toList();
      if (matches.isEmpty) {
        comment.clear();
        continue;
      }

      // A key can only be attributed when the line sets exactly one value.
      final assignedKey = matches.length == 1
          ? _assignmentPattern.firstMatch(line)?.group(1)
          : null;

      for (final match in matches) {
        final name = match.group(1)!;
        final existing = found[name];
        if (existing == null) {
          found[name] = ServiceVariable(
            name: name,
            key: assignedKey,
            documentation: comment.isEmpty ? null : comment.join(' '),
            sources: [path],
          );
        } else if (!existing.sources.contains(path)) {
          existing.sources.add(path);
        }
      }
      comment.clear();
    }
  }

  return found.values.toList();
}

/// Compares dotted versions such as `3.4.0` numerically, tolerating garbage.
int _compareDottedVersions(String a, String b) {
  final left = a.split('.');
  final right = b.split('.');
  final length = left.length > right.length ? left.length : right.length;

  for (var i = 0; i < length; i++) {
    final x = i < left.length ? int.tryParse(left[i].trim()) ?? 0 : 0;
    final y = i < right.length ? int.tryParse(right[i].trim()) ?? 0 : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

int _directorySuffixVersion(String serviceId) {
  final match = _versionSuffixPattern.firstMatch(serviceId);
  return match == null ? 0 : int.parse(match.group(1)!);
}

/// Orders two releases of the same service, newest last.
int compareServiceVersions(MarketplaceService a, MarketplaceService b) {
  final byVersion = _compareDottedVersions(a.version, b.version);
  if (byVersion != 0) return byVersion;
  // `n8n` and `n8n_v2` could declare the same version; prefer the later dir.
  return _directorySuffixVersion(a.id).compareTo(
    _directorySuffixVersion(b.id),
  );
}

class ServiceFirewallRule {
  const ServiceFirewallRule({
    required this.port,
    required this.protocol,
    required this.direction,
    required this.description,
  });

  final int port;
  final String protocol;
  final String direction;
  final String description;
}

class ServiceStorageRequirement {
  const ServiceStorageRequirement({
    required this.path,
    required this.minSizeGb,
    required this.description,
  });

  final String path;
  final int minSizeGb;
  final String description;
}

class ServiceResources {
  const ServiceResources({required this.minCpu, required this.minMemoryGb});

  final int minCpu;
  final int minMemoryGb;
}

/// A file the manifest wants written onto the guest, declared under `files:`.
class ServiceFileSpec {
  const ServiceFileSpec({
    required this.source,
    required this.destination,
    required this.owner,
    required this.permissions,
  });

  final String source;
  final String destination;
  final String owner;
  final String permissions;
}

/// One `services/<id>/` directory from the elemento-marketplace library.
class MarketplaceService {
  const MarketplaceService({
    required this.id,
    required this.name,
    required this.displayName,
    required this.version,
    required this.description,
    required this.entrypoint,
    required this.files,
    required this.firewall,
    required this.storage,
    required this.resources,
    required this.variables,
    required this.sources,
    this.readme,
    this.healthcheck,
    this.serviceInfo,
  });

  /// Directory name, e.g. `qdrant_v1`. Unique within the library.
  final String id;

  /// `metadata.name`, which in practice matches [id].
  final String name;
  final String displayName;
  final String version;
  final String description;
  final String? readme;

  /// Guest paths of the optional healthcheck / connection-info helpers.
  final String? healthcheck;
  final String? serviceInfo;

  /// Relative path of the cloud-init document, from `cloud_init.entrypoint`.
  final String entrypoint;
  final List<ServiceFileSpec> files;
  final List<ServiceFirewallRule> firewall;
  final List<ServiceStorageRequirement> storage;
  final ServiceResources resources;

  /// Every `{{placeholder}}` the service accepts, in source order.
  final List<ServiceVariable> variables;

  /// Verbatim contents of the service directory, keyed by relative path.
  final Map<String, String> sources;

  List<int> get exposedPorts {
    final ports = firewall
        .where((rule) => rule.direction == 'ingress')
        .map((rule) => rule.port)
        .toSet()
        .toList();
    ports.sort();
    return ports;
  }

  /// Total guest storage the manifest asks for, across all declared paths.
  int get totalStorageGb =>
      storage.fold(0, (sum, entry) => sum + entry.minSizeGb);

  static MarketplaceService fromBundleEntry(Map<String, Object?> entry) {
    final id = entry['id'] as String;
    final sources = (entry['files'] as Map).cast<String, String>();

    final manifestText = sources['service.yaml'];
    if (manifestText == null) {
      throw FormatException('Service "$id" has no service.yaml');
    }
    final manifest = _asMap(loadYaml(manifestText));
    final metadata = _asMap(manifest['metadata']);
    final runtime = _asMap(manifest['runtime']);
    final prerequisites = _asMap(manifest['prerequisites']);
    final resources = _asMap(prerequisites['resources']);

    final entrypoint =
        _asMap(manifest['cloud_init'])['entrypoint'] as String? ??
            'cloud-init.yaml';
    if (!sources.containsKey(entrypoint)) {
      throw FormatException(
        'Service "$id" declares entrypoint "$entrypoint" which is not bundled',
      );
    }

    return MarketplaceService(
      id: id,
      name: metadata['name'] as String? ?? id,
      displayName: metadata['display_name'] as String? ?? id,
      version: '${metadata['version'] ?? ''}',
      // Manifests use folded block scalars, which keep a trailing newline.
      description: (metadata['description'] as String? ?? '').trim(),
      readme: sources['README.md'],
      healthcheck: runtime['healthcheck'] as String?,
      serviceInfo: runtime['service_info'] as String?,
      entrypoint: entrypoint,
      files: _asList(manifest['files']).map((raw) {
        final spec = _asMap(raw);
        return ServiceFileSpec(
          source: spec['source'] as String,
          destination: spec['destination'] as String,
          owner: spec['owner'] as String? ?? 'root:root',
          permissions: '${spec['permissions'] ?? '0644'}',
        );
      }).toList(),
      firewall: _asList(prerequisites['firewall']).map((raw) {
        final rule = _asMap(raw);
        return ServiceFirewallRule(
          port: rule['port'] as int? ?? 0,
          protocol: rule['protocol'] as String? ?? 'tcp',
          direction: rule['direction'] as String? ?? 'ingress',
          description: rule['description'] as String? ?? '',
        );
      }).toList(),
      storage: _asList(prerequisites['storage']).map((raw) {
        final entry = _asMap(raw);
        return ServiceStorageRequirement(
          path: entry['path'] as String? ?? '',
          minSizeGb: entry['min_size_gb'] as int? ?? 0,
          description: entry['description'] as String? ?? '',
        );
      }).toList(),
      resources: ServiceResources(
        minCpu: resources['min_cpu'] as int? ?? 1,
        minMemoryGb: resources['min_memory_gb'] as int? ?? 1,
      ),
      variables: _extractVariables(sources),
      sources: sources,
    );
  }
}

class MarketplaceLibrary {
  const MarketplaceLibrary({required this.commit, required this.services});

  /// Commit of the pinned `3rd-party/elemento-marketplace` submodule the
  /// bundle was generated from.
  final String commit;
  final List<MarketplaceService> services;

  MarketplaceService? byId(String id) =>
      services.firstWhereOrNull((service) => service.id == id);

  static MarketplaceLibrary parse(String json) {
    final bundle = jsonDecode(json) as Map<String, Object?>;
    final schema = bundle['schema'];
    if (schema != 1) {
      throw FormatException('Unsupported marketplace bundle schema: $schema');
    }

    final all = _asList(bundle['services'])
        .map((entry) =>
            MarketplaceService.fromBundleEntry(_asMap(entry).cast()))
        .toList();

    // The library keeps superseded releases side by side (n8n, n8n_v2,
    // n8n_v3); only offer the newest of each family.
    final newestByFamily = <String, MarketplaceService>{};
    for (final service in all) {
      final family = serviceFamily(service.id);
      final incumbent = newestByFamily[family];
      if (incumbent == null || compareServiceVersions(service, incumbent) > 0) {
        newestByFamily[family] = service;
      }
    }

    final services = newestByFamily.values.toList();
    services.sort((a, b) => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ));

    return MarketplaceLibrary(
      commit: _asMap(bundle['source'])['commit'] as String? ?? 'unknown',
      services: services,
    );
  }

  static Future<MarketplaceLibrary> load([AssetBundle? assets]) async {
    final json =
        await (assets ?? rootBundle).loadString(marketplaceBundleAsset);
    return parse(json);
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value == null) return const {};
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item as Object?));
  }
  throw FormatException('Expected a mapping but got ${value.runtimeType}');
}

List<Object?> _asList(Object? value) {
  if (value == null) return const [];
  if (value is List) return value;
  throw FormatException('Expected a list but got ${value.runtimeType}');
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

final marketplaceLibraryProvider = FutureProvider<MarketplaceLibrary>((ref) {
  return MarketplaceLibrary.load();
});
