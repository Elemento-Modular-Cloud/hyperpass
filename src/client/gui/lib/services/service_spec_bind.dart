import 'dart:convert';

import 'service_spec.dart';

/// Looks up a JSON Pointer (`/a/b/0`) in a decoded JSON tree.
///
/// RFC 6901 unescaping of `~1` / `~0` is applied. Returns null when any
/// segment is missing.
Object? lookupPointer(Object? root, String pointer) {
  if (pointer.isEmpty) return root;
  if (pointer == '/') {
    return root is Map ? root[''] : null;
  }
  if (!pointer.startsWith('/')) {
    throw FormatException('JSON Pointer must start with "/": $pointer');
  }

  Object? current = root;
  for (final raw in pointer.substring(1).split('/')) {
    final token = raw.replaceAll('~1', '/').replaceAll('~0', '~');
    if (current is Map) {
      if (!current.containsKey(token)) return null;
      current = current[token];
      continue;
    }
    if (current is List) {
      final index = int.tryParse(token);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
      continue;
    }
    return null;
  }
  return current;
}

/// Turns a JSON Pointer result into a placeholder substitution string.
String stringifyPointerValue(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return jsonEncode(value);
}

/// Copies a producer's live `service-info` values onto a consumer's inputs
/// for one named contract.
///
/// Returns `{ consumerInputName: value }` for every contract field that
/// resolved. Throws if either side does not declare the contract, or if a
/// mapped pointer is missing from [serviceInfo].
Map<String, String> bindContract({
  required ServiceSpec producer,
  required Map<String, Object?> serviceInfo,
  required ServiceSpec consumer,
  required String contractId,
}) {
  final provided = producer.provides[contractId];
  if (provided == null) {
    throw StateError('Producer does not provide contract "$contractId"');
  }
  final required = consumer.requires[contractId];
  if (required == null) {
    throw StateError('Consumer does not require contract "$contractId"');
  }

  final bound = <String, String>{};
  for (final field in required.inputs.entries) {
    final consumerInput = consumer.inputs[field.value];
    final optionalField =
        required.optional || (consumerInput != null && !consumerInput.required);
    final pointer = provided.outputs[field.key];
    if (pointer == null) {
      if (optionalField) continue;
      throw StateError(
        'Contract "$contractId" field "${field.key}" is not provided',
      );
    }
    final value = lookupPointer(serviceInfo, pointer);
    if (value == null) {
      if (optionalField) continue;
      throw StateError(
        'service-info has no value at "$pointer" for contract "$contractId"',
      );
    }
    bound[field.value] = stringifyPointerValue(value);
  }
  return bound;
}

/// One producer plus its live `service-info` for [bindContracts].
class ContractProducer {
  const ContractProducer({
    required this.spec,
    required this.serviceInfo,
  });

  final ServiceSpec spec;
  final Map<String, Object?> serviceInfo;
}

String _defaultPeerModel(int index) =>
    index == 0 ? 'local' : 'local-${index + 1}';

String? _producerFieldValue({
  required ServiceSpec producer,
  required Map<String, Object?> serviceInfo,
  required String contractId,
  required String fieldName,
  required bool requiredField,
}) {
  final provided = producer.provides[contractId];
  if (provided == null) {
    throw StateError('Producer does not provide contract "$contractId"');
  }
  final pointer = provided.outputs[fieldName];
  if (pointer == null) {
    if (requiredField) {
      throw StateError(
        'Contract "$contractId" field "$fieldName" is not provided',
      );
    }
    return null;
  }
  final value = lookupPointer(serviceInfo, pointer);
  if (value == null) {
    if (requiredField) {
      throw StateError(
        'service-info has no value at "$pointer" for contract "$contractId"',
      );
    }
    return null;
  }
  final text = stringifyPointerValue(value).trim();
  return text.isEmpty ? null : text;
}

/// Binds N producers onto a consumer. One producer uses scalar `inputs:`;
/// N > 1 joins `collect:` targets with `;`.
Map<String, String> bindContracts({
  required List<ContractProducer> producers,
  required ServiceSpec consumer,
  required String contractId,
}) {
  final required = consumer.requires[contractId];
  if (required == null) {
    throw StateError('Consumer does not require contract "$contractId"');
  }

  final count = producers.length;
  if (count < required.min) {
    throw StateError(
      '${consumer.name} requires at least ${required.min} $contractId '
      'producer(s), got $count',
    );
  }
  final max = required.max;
  if (max != null && count > max) {
    throw StateError(
      '${consumer.name} accepts at most $max $contractId producer(s), '
      'got $count',
    );
  }
  if (count == 0) return {};
  if (count == 1) {
    return bindContract(
      producer: producers.single.spec,
      serviceInfo: producers.single.serviceInfo,
      consumer: consumer,
      contractId: contractId,
    );
  }

  if (required.collect.isEmpty) {
    throw StateError(
      '${consumer.name} requires.$contractId has no collect: mapping '
      'for $count producers',
    );
  }

  final bound = <String, String>{};
  for (final field in required.collect.entries) {
    final values = <String>[];
    for (var index = 0; index < producers.length; index++) {
      final source = producers[index];
      var value = _producerFieldValue(
        producer: source.spec,
        serviceInfo: source.serviceInfo,
        contractId: contractId,
        fieldName: field.key,
        requiredField: false,
      );
      if (field.key == 'ca_url') {
        if (value != null && !values.contains(value)) {
          values.add(value);
        }
        continue;
      }
      if (value == null && field.key == 'model') {
        value = _defaultPeerModel(index);
      }
      if (value == null) continue;
      values.add(value);
    }
    if (values.isNotEmpty) {
      bound[field.value] = values.join(';');
    }
  }
  return bound;
}
