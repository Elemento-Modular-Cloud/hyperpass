import 'package:yaml/yaml.dart';

import 'gateway_ca.dart';
import 'service_library.dart';

/// Renders a marketplace service directory into a single cloud-config
/// document, mirroring `CloudinitManager._render_directory_service` in the
/// elemento-marketplace repo: the `files:` declared by the manifest are folded
/// into `write_files`, then root filesystem growth is injected.
///
/// [variables] fills `{{placeholder}}` values. Leaving them out is safe and is
/// the intended zero-config path: each service's `configure-*.sh` detects
/// leftover placeholders and generates secrets on first boot.
String renderServiceCloudInit(
  MarketplaceService service, {
  Map<String, String> variables = const {},
  String? gatewayCaPem,
}) {
  final entrypointText = service.sources[service.entrypoint]!;
  final parsed = _toPlain(loadYaml(entrypointText));
  if (parsed is! Map<String, Object?>) {
    throw FormatException(
      'Service "${service.id}" entrypoint is not a cloud-config mapping',
    );
  }

  final config = _substituteIn(parsed, variables) as Map<String, Object?>;

  final writeFiles = _mutableList(config['write_files']);
  for (final spec in service.files) {
    final content = service.sources[spec.source];
    if (content == null) {
      throw FormatException(
        'Service "${service.id}" declares file "${spec.source}" '
        'which is not bundled',
      );
    }
    writeFiles.add(<String, Object?>{
      'path': _substituteString(spec.destination, variables),
      'owner': _substituteString(spec.owner, variables),
      'permissions': _substituteString(spec.permissions, variables),
      'content': _substituteString(content, variables),
    });
  }
  if (writeFiles.isNotEmpty) {
    config['write_files'] = writeFiles;
  }

  return emitCloudConfig(
    _ensureGatewayCa(_ensureRootfsGrowth(config), gatewayCaPem),
  );
}

// ---------------------------------------------------------------------------
// Root filesystem growth
// ---------------------------------------------------------------------------

/// Cloud images often leave `/` at the original image size even when the boot
/// disk is larger, so growth is forced without clobbering anything a recipe
/// already set.
Map<String, Object?> _ensureRootfsGrowth(Map<String, Object?> config) {
  final result = Map<String, Object?>.of(config);

  result.putIfAbsent(
    'growpart',
    () => <String, Object?>{
      'mode': 'auto',
      'devices': <Object?>['/'],
      'ignore_growroot_disabled': true,
    },
  );
  result.putIfAbsent('resize_rootfs', () => true);

  final packages = _mutableList(result['packages']);
  if (!packages.contains('cloud-guest-utils')) {
    packages.insert(0, 'cloud-guest-utils');
    result['packages'] = packages;
  }

  final runcmd = _mutableList(result['runcmd']);
  if (!_runcmdGrowsRootfs(runcmd)) {
    runcmd.insert(0, _rootfsGrowRuncmd);
    result['runcmd'] = runcmd;
  }

  // Keep growth directives at the top of the rendered document.
  final ordered = <String, Object?>{};
  for (final key in const ['growpart', 'resize_rootfs']) {
    if (result.containsKey(key)) ordered[key] = result.remove(key);
  }
  ordered.addAll(result);
  return ordered;
}

const _rootfsGrowRuncmd =
    r"""/bin/sh -c 'set -eux; src=$(readlink -f "$(findmnt -n -o SOURCE /)"); disk="/dev/$(lsblk -no PKNAME "$src")"; part=$(lsblk -no PARTN "$src"); growpart "$disk" "$part" || true; resize2fs "$src" || true; df -h /'""";

/// Installs the LaunchPad HTTPS CA so guests trust https://192.168.67.1:7777
/// before marketplace `runcmd` (configure + docker compose) runs.
Map<String, Object?> _ensureGatewayCa(
  Map<String, Object?> config,
  String? gatewayCaPem,
) {
  final pem = gatewayCaPem?.trim() ?? '';
  if (!looksLikePemCertificate(pem)) return config;

  final result = Map<String, Object?>.of(config);

  final writeFiles = _mutableList(result['write_files']);
  final already = writeFiles.any(
    (entry) =>
        entry is Map && entry['path'] == gatewayCaGuestPath,
  );
  if (!already) {
    writeFiles.insert(0, <String, Object?>{
      'path': gatewayCaGuestPath,
      'owner': 'root:root',
      'permissions': '0644',
      'content': pem.endsWith('\n') ? pem : '$pem\n',
    });
    result['write_files'] = writeFiles;
  }

  final packages = _mutableList(result['packages']);
  if (!packages.contains('ca-certificates')) {
    packages.insert(0, 'ca-certificates');
    result['packages'] = packages;
  }

  final runcmd = _mutableList(result['runcmd']);
  if (!_runcmdUpdatesCaCertificates(runcmd)) {
    runcmd.insert(0, gatewayCaUpdateRuncmd);
    result['runcmd'] = runcmd;
  }

  return result;
}

bool _runcmdUpdatesCaCertificates(List<Object?> runcmd) {
  for (final entry in runcmd) {
    if (entry is String && entry.contains('update-ca-certificates')) {
      return true;
    }
    if (entry is List &&
        entry.any(
          (part) =>
              part is String && part.contains('update-ca-certificates'),
        )) {
      return true;
    }
  }
  return false;
}

bool _runcmdGrowsRootfs(List<Object?> runcmd) {
  for (final entry in runcmd) {
    if (entry is String &&
        entry.contains('growpart') &&
        entry.contains('resize2fs')) {
      return true;
    }
    if (entry is List &&
        entry.any((part) => part is String && part.contains('growpart'))) {
      return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Placeholder substitution
// ---------------------------------------------------------------------------

String _substituteString(String value, Map<String, String> variables) {
  if (variables.isEmpty) return value;
  var result = value;
  variables.forEach((key, replacement) {
    result = result.replaceAll('{{$key}}', replacement);
  });
  return result;
}

Object? _substituteIn(Object? value, Map<String, String> variables) {
  if (variables.isEmpty) return value;
  if (value is String) return _substituteString(value, variables);
  if (value is List) {
    return value.map((item) => _substituteIn(item, variables)).toList();
  }
  if (value is Map<String, Object?>) {
    return value.map(
      (key, item) => MapEntry(
        _substituteString(key, variables),
        _substituteIn(item, variables),
      ),
    );
  }
  return value;
}

// ---------------------------------------------------------------------------
// YAML emission
//
// The `yaml` package only parses, so cloud-config is emitted here. Output is
// block style with literal block scalars for multi-line file contents, which
// is what the daemon's yaml-cpp loader and cloud-init both expect.
// ---------------------------------------------------------------------------

String emitCloudConfig(Map<String, Object?> config) {
  final out = StringBuffer('#cloud-config\n');
  _writeMap(out, config, 0);
  return out.toString();
}

void _writeMap(StringBuffer out, Map<String, Object?> map, int indent) {
  final pad = ' ' * indent;
  map.forEach((key, value) {
    final prefix = '$pad${_formatScalar(key)}:';
    if (value is Map) {
      final nested = value.cast<String, Object?>();
      if (nested.isEmpty) {
        out.writeln('$prefix {}');
      } else {
        out.writeln(prefix);
        _writeMap(out, nested, indent + 2);
      }
    } else if (value is List) {
      if (value.isEmpty) {
        out.writeln('$prefix []');
      } else {
        out.writeln(prefix);
        _writeList(out, value, indent + 2);
      }
    } else {
      _writeScalar(out, prefix, value, indent);
    }
  });
}

void _writeList(StringBuffer out, List<Object?> list, int indent) {
  final pad = ' ' * indent;
  for (final item in list) {
    if (item is Map) {
      final nested = item.cast<String, Object?>();
      if (nested.isEmpty) {
        out.writeln('$pad- {}');
      } else {
        out.writeln('$pad-');
        _writeMap(out, nested, indent + 2);
      }
    } else if (item is List) {
      if (item.isEmpty) {
        out.writeln('$pad- []');
      } else {
        out.writeln('$pad-');
        _writeList(out, item, indent + 2);
      }
    } else {
      _writeScalar(out, '$pad-', item, indent);
    }
  }
}

void _writeScalar(
  StringBuffer out,
  String prefix,
  Object? value,
  int indent,
) {
  if (value is String && value.contains('\n') && _canUseBlockScalar(value)) {
    out.writeln('$prefix ${_blockScalarHeader(value)}');
    _writeBlockScalarBody(out, value, indent + 2);
  } else {
    out.writeln('$prefix ${_formatScalar(value)}');
  }
}

/// A literal block scalar takes its indentation from the first non-empty line,
/// so content that starts blank or indented would need an explicit indentation
/// indicator. Those cases fall back to a quoted scalar instead.
bool _canUseBlockScalar(String value) {
  if (value.contains('\r')) return false;
  if (_controlCharacters.hasMatch(value)) return false;
  final firstLine = value.substring(0, value.indexOf('\n'));
  if (firstLine.isEmpty) return false;
  return !firstLine.startsWith(' ') && !firstLine.startsWith('\t');
}

String _blockScalarHeader(String value) {
  final trailing = _trailingNewlines(value);
  if (trailing == 0) return '|-'; // strip
  if (trailing == 1) return '|'; // clip
  return '|+'; // keep
}

void _writeBlockScalarBody(StringBuffer out, String value, int indent) {
  final pad = ' ' * indent;
  final lines = value.split('\n');
  // A trailing newline produces an empty final element that the chomping
  // indicator already accounts for.
  if (_trailingNewlines(value) > 0) lines.removeLast();
  for (final line in lines) {
    out.writeln(line.isEmpty ? '' : '$pad$line');
  }
}

int _trailingNewlines(String value) {
  var count = 0;
  var index = value.length;
  while (index > 0 && value[index - 1] == '\n') {
    count++;
    index--;
  }
  return count;
}

String _formatScalar(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) return '$value';
  final text = '$value';
  return _needsQuoting(text) ? _quote(text) : text;
}

/// Characters that change meaning at the start of a plain scalar.
const _leadingIndicators = r'-?:,[]{}#&*!|>' '\'"' r'%@`';
final _controlCharacters = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');
final _booleanLikeWords = RegExp(
  r'^(y|n|yes|no|true|false|on|off|null|~)$',
  caseSensitive: false,
);

bool _needsQuoting(String value) {
  if (value.isEmpty) return true;
  if (value.trim() != value) return true;
  if (value.contains('\n') || value.contains('\r')) return true;
  if (_leadingIndicators.contains(value[0])) return true;
  if (value.contains(': ') || value.endsWith(':')) return true;
  if (value.contains(' #')) return true;
  // Quote anything YAML would otherwise decode as a non-string, so that e.g.
  // permissions "0600" survives as a string.
  if (_booleanLikeWords.hasMatch(value)) return true;
  if (num.tryParse(value) != null) return true;
  return false;
}

String _quote(String value) {
  if (value.contains('\n') ||
      value.contains('\r') ||
      _controlCharacters.hasMatch(value)) {
    return '"${_escapeForDoubleQuotes(value)}"';
  }
  return "'${value.replaceAll("'", "''")}'";
}

String _escapeForDoubleQuotes(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    switch (rune) {
      case 0x5c: // backslash
        out.write(r'\\');
      case 0x22: // double quote
        out.write(r'\"');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (rune < 0x20 || rune == 0x7f) {
          out.write('\\x${rune.toRadixString(16).padLeft(2, '0')}');
        } else {
          out.writeCharCode(rune);
        }
    }
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Converts the immutable `YamlMap`/`YamlList` tree into plain, mutable
/// collections that can be rewritten before emission.
Object? _toPlain(Object? value) {
  if (value is YamlMap) {
    return <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}': _toPlain(entry.value),
    };
  }
  if (value is YamlList) {
    return value.map(_toPlain).toList();
  }
  if (value is YamlScalar) return value.value;
  return value;
}

List<Object?> _mutableList(Object? value) {
  if (value is List) return List<Object?>.of(value);
  return <Object?>[];
}
