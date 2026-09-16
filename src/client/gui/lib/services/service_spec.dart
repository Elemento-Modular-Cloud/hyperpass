import 'package:yaml/yaml.dart';

/// OpenAI-compatible HTTP API (`base_url` + `api_key`, optional `model` / `ca_url`).
const openaiCompatibleContract = 'openai_compatible';

/// Caddy `tls internal` CA bundle advertised by HTTPS marketplace services.
const caddyCaContract = 'caddy_ca';

/// One `inputs:` entry from `elemento.spec/v1`.
class ServiceSpecInput {
  const ServiceSpecInput({
    required this.name,
    required this.type,
    required this.required,
    required this.secret,
    required this.generated,
    this.pattern,
    this.description,
  });

  final String name;
  final String type;
  final bool required;
  final bool secret;
  final bool generated;
  final String? pattern;
  final String? description;
}

/// One `outputs:` entry, keyed by a JSON Pointer into `service-info`.
class ServiceSpecOutput {
  const ServiceSpecOutput({
    required this.pointer,
    required this.type,
    this.pattern,
    this.description,
  });

  final String pointer;
  final String type;
  final String? pattern;
  final String? description;
}

/// Conditional required-together group (`when` input implies `require`).
class ServiceSpecGroup {
  const ServiceSpecGroup({
    required this.name,
    required this.when,
    required this.require,
  });

  final String name;
  final String when;
  final List<String> require;
}

/// Resolved `min` / `max` for a provides or requires port.
///
/// [max] is null when the port is unbounded (`max: null` or `collect:` with
/// no explicit max).
class BindingCardinality {
  const BindingCardinality({required this.min, this.max});

  final int min;
  final int? max;
}

/// Marketplace `binding_cardinality`: omitted min is 0 if optional else 1;
/// omitted max is unbounded when [collect] is present, otherwise 1.
BindingCardinality bindingCardinality({
  required Map<String, Object?> body,
  Map<String, String> collect = const {},
}) {
  final hasCollect = collect.isNotEmpty;
  final optional = _asBool(body['optional']);

  final int minV;
  if (body.containsKey('min') && body['min'] != null) {
    minV = _asNonNegInt(body['min']) ?? (optional ? 0 : 1);
  } else {
    minV = optional ? 0 : 1;
  }

  final int? maxV;
  if (body.containsKey('max')) {
    final rawMax = body['max'];
    maxV = rawMax == null ? null : _asNonNegInt(rawMax) ?? 1;
  } else if (hasCollect) {
    maxV = null;
  } else {
    maxV = 1;
  }

  return BindingCardinality(min: minV, max: maxV);
}

/// Incoming-edge cap for a consumer port. Null means unbounded.
int? incomingLimit(ServiceContractRequires requires) => requires.max;

/// True when the consumer port accepts more than one producer.
bool allowsManyIncoming(ServiceContractRequires requires) => requires.max != 1;

/// A contract this service exposes, mapping contract fields to output pointers.
class ServiceContractProvides {
  const ServiceContractProvides({
    required this.contractId,
    required this.outputs,
    this.min = 1,
    this.max = 1,
  });

  final String contractId;

  /// Contract field name → JSON Pointer.
  final Map<String, String> outputs;

  final int min;

  /// How many APIs this node *is*. Null is unbounded. Not a fan-out cap.
  final int? max;
}

/// A contract this service consumes, mapping contract fields to input names.
class ServiceContractRequires {
  const ServiceContractRequires({
    required this.contractId,
    required this.optional,
    required this.inputs,
    this.min = 0,
    this.max = 1,
    this.collect = const {},
  });

  final String contractId;
  final bool optional;

  /// Contract field name → consumer input / placeholder name.
  final Map<String, String> inputs;

  final int min;

  /// Incoming producer cap. Null is unbounded.
  final int? max;

  /// Contract field → semicolon_list input, used when N > 1 producers.
  final Map<String, String> collect;
}

/// Formal I/O for a marketplace service (`spec.yaml`, `elemento.spec/v1`).
class ServiceSpec {
  const ServiceSpec({
    required this.name,
    required this.inputs,
    required this.outputs,
    required this.groups,
    required this.provides,
    required this.requires,
  });

  final String name;
  final Map<String, ServiceSpecInput> inputs;
  final Map<String, ServiceSpecOutput> outputs;
  final List<ServiceSpecGroup> groups;
  final Map<String, ServiceContractProvides> provides;
  final Map<String, ServiceContractRequires> requires;

  bool get hasContracts => provides.isNotEmpty || requires.isNotEmpty;

  bool get hasHttpOutputs => outputs.values.any(
        (output) => output.type == 'url' || output.type == 'ca_url',
      );

  /// Host-local LLM: OpenAI-compatible `/v1` that consumers can wire.
  factory ServiceSpec.openaiCompatibleProvider(String name) {
    return ServiceSpec(
      name: name,
      inputs: const {},
      outputs: {
        '/endpoints/api': const ServiceSpecOutput(
          pointer: '/endpoints/api',
          type: 'url',
        ),
        '/credentials/tokens': const ServiceSpecOutput(
          pointer: '/credentials/tokens',
          type: 'array',
        ),
        '/model': const ServiceSpecOutput(
          pointer: '/model',
          type: 'model_id',
        ),
      },
      groups: const [],
      provides: {
        openaiCompatibleContract: const ServiceContractProvides(
          contractId: openaiCompatibleContract,
          outputs: {
            'base_url': '/endpoints/api',
            'api_key': '/credentials/tokens/0',
            'model': '/model',
          },
        ),
      },
      requires: const {},
    );
  }

  /// Placeholder-scan fallback when `spec.yaml` is missing or empty.
  factory ServiceSpec.fromInputNames(
    String name,
    Map<String, String?> inputDescriptions,
  ) {
    return ServiceSpec(
      name: name,
      inputs: {
        for (final entry in inputDescriptions.entries)
          entry.key: ServiceSpecInput(
            name: entry.key,
            type: 'string',
            required: false,
            secret: false,
            generated: false,
            description: entry.value,
          ),
      },
      outputs: const {},
      groups: const [],
      provides: const {},
      requires: const {},
    );
  }

  static ServiceSpec? tryParse(String yamlText, {String? serviceId}) {
    try {
      return parse(yamlText, serviceId: serviceId);
    } catch (_) {
      return null;
    }
  }

  static ServiceSpec parse(String yamlText, {String? serviceId}) {
    final decoded = loadYaml(yamlText);
    final root = _asMap(decoded);
    final metadata = _asMap(root['metadata']);
    final name = metadata['name'] as String? ?? serviceId ?? '';

    final inputs = <String, ServiceSpecInput>{};
    for (final entry in _asMap(root['inputs']).entries) {
      final body = _asMap(entry.value);
      inputs[entry.key] = ServiceSpecInput(
        name: entry.key,
        type: '${body['type'] ?? 'string'}',
        required: _asBool(body['required']),
        secret: _asBool(body['secret']),
        generated: _asBool(body['generated']),
        pattern: body['pattern'] == null ? null : '${body['pattern']}',
        description:
            body['description'] == null ? null : '${body['description']}',
      );
    }

    final outputs = <String, ServiceSpecOutput>{};
    for (final entry in _asMap(root['outputs']).entries) {
      final body = _asMap(entry.value);
      outputs[entry.key] = ServiceSpecOutput(
        pointer: entry.key,
        type: '${body['type'] ?? 'string'}',
        pattern: body['pattern'] == null ? null : '${body['pattern']}',
        description:
            body['description'] == null ? null : '${body['description']}',
      );
    }

    final groups = <ServiceSpecGroup>[];
    for (final entry in _asMap(root['groups']).entries) {
      final body = _asMap(entry.value);
      final when = '${body['when'] ?? ''}';
      if (when.isEmpty) continue;
      groups.add(
        ServiceSpecGroup(
          name: entry.key,
          when: when,
          require: _asStringList(body['require']),
        ),
      );
    }

    final provides = <String, ServiceContractProvides>{};
    for (final entry in _asMap(root['provides']).entries) {
      final body = _asMap(entry.value);
      final outputsMap = _stringMap(body['outputs']);
      final cardinality = bindingCardinality(body: body);
      provides[entry.key] = ServiceContractProvides(
        contractId: entry.key,
        outputs: outputsMap,
        min: cardinality.min,
        max: cardinality.max,
      );
    }

    final requires = <String, ServiceContractRequires>{};
    for (final entry in _asMap(root['requires']).entries) {
      final body = _asMap(entry.value);
      final inputsMap = _stringMap(body['inputs']);
      final collect = _stringMap(body['collect']);
      final cardinality = bindingCardinality(body: body, collect: collect);
      requires[entry.key] = ServiceContractRequires(
        contractId: entry.key,
        optional: _asBool(body['optional'], fallback: true),
        inputs: inputsMap,
        min: cardinality.min,
        max: cardinality.max,
        collect: collect,
      );
    }

    return ServiceSpec(
      name: name,
      inputs: inputs,
      outputs: outputs,
      groups: groups,
      provides: provides,
      requires: requires,
    );
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value == null) return const {};
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item as Object?));
  }
  throw FormatException('Expected a mapping but got ${value.runtimeType}');
}

Map<String, String> _stringMap(Object? value) {
  return {
    for (final field in _asMap(value).entries)
      if (field.value != null) field.key: '${field.value}',
  };
}

int? _asNonNegInt(Object? value) {
  if (value is int) return value >= 0 ? value : null;
  if (value is num && value >= 0 && value == value.roundToDouble()) {
    return value.toInt();
  }
  final parsed = int.tryParse('$value');
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

List<String> _asStringList(Object? value) {
  if (value == null) return const [];
  if (value is List) return [for (final item in value) '$item'];
  throw FormatException('Expected a list but got ${value.runtimeType}');
}

bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value == null) return fallback;
  final text = '$value'.toLowerCase();
  if (text == 'true' || text == 'yes') return true;
  if (text == 'false' || text == 'no') return false;
  return fallback;
}
