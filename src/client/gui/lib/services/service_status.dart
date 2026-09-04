import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'service_guest.dart';
import 'service_library.dart';

const defaultHealthcheckPath = '/opt/elemento/bin/healthcheck';
const defaultServiceInfoPath = '/opt/elemento/bin/service-info';

class ServiceInfoDocument {
  const ServiceInfoDocument({
    required this.apiVersion,
    required this.service,
    required this.status,
    required this.endpoints,
    required this.credentials,
    required this.backends,
    required this.raw,
  });

  final String apiVersion;
  final String service;
  final String status;
  final Map<String, String> endpoints;
  final Map<String, String> credentials;
  final List<Map<String, String>> backends;
  final Map<String, Object?> raw;

  factory ServiceInfoDocument.parse(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw FormatException('service-info did not return a JSON object');
    }
    final map = decoded.map((k, v) => MapEntry('$k', v as Object?));

    final endpoints = <String, String>{};
    final endpointsRaw = map['endpoints'];
    if (endpointsRaw is Map) {
      for (final entry in endpointsRaw.entries) {
        if (entry.value != null) {
          endpoints['${entry.key}'] = '${entry.value}';
        }
      }
    }

    final credentials = <String, String>{};
    final credentialsRaw = map['credentials'];
    if (credentialsRaw is Map) {
      for (final entry in credentialsRaw.entries) {
        final value = entry.value;
        if (value == null) continue;
        if (value is List) {
          credentials['${entry.key}'] = value.map((e) => '$e').join(', ');
        } else if (value is Map) {
          credentials['${entry.key}'] = jsonEncode(value);
        } else {
          credentials['${entry.key}'] = '$value';
        }
      }
    }

    final backends = <Map<String, String>>[];
    final backendsRaw = map['backends'];
    if (backendsRaw is List) {
      for (final item in backendsRaw) {
        if (item is! Map) continue;
        backends.add({
          for (final entry in item.entries)
            if (entry.value != null) '${entry.key}': '${entry.value}',
        });
      }
    }

    return ServiceInfoDocument(
      apiVersion: '${map['api_version'] ?? ''}',
      service: '${map['service'] ?? ''}',
      status: '${map['status'] ?? ''}',
      endpoints: endpoints,
      credentials: credentials,
      backends: backends,
      raw: map,
    );
  }
}

enum ServiceHealthState { unknown, healthy, unhealthy, unreachable }

class ServiceGuestStatus {
  const ServiceGuestStatus({
    required this.health,
    this.healthDetail,
    this.info,
    this.infoError,
  });

  final ServiceHealthState health;
  final String? healthDetail;
  final ServiceInfoDocument? info;
  final String? infoError;
}

Future<ServiceGuestStatus> fetchServiceGuestStatus({
  required GrpcClient grpc,
  required String instanceName,
  String healthcheckPath = defaultHealthcheckPath,
  String serviceInfoPath = defaultServiceInfoPath,
}) async {
  try {
    return await withGuestSsh(grpc, instanceName, (client) async {
      final health = await runGuestCommand(
        client,
        guestPrivilegedCommand(healthcheckPath),
      );
      final healthState = health.exitCode == 0
          ? ServiceHealthState.healthy
          : ServiceHealthState.unhealthy;
      final healthDetail = health.exitCode == 0
          ? null
          : (health.stderr.isNotEmpty
              ? health.stderr
              : (health.stdout.isNotEmpty
                  ? health.stdout
                  : 'exit ${health.exitCode}'));

      ServiceInfoDocument? info;
      String? infoError;
      try {
        final infoResult = await runGuestCommand(
          client,
          guestPrivilegedCommand(serviceInfoPath),
        );
        if (infoResult.exitCode != 0) {
          infoError = infoResult.stderr.isNotEmpty
              ? infoResult.stderr
              : 'service-info exited ${infoResult.exitCode}';
        } else if (infoResult.stdout.isEmpty) {
          infoError = 'service-info returned no output';
        } else {
          info = ServiceInfoDocument.parse(infoResult.stdout);
        }
      } catch (error) {
        infoError = '$error';
      }

      return ServiceGuestStatus(
        health: healthState,
        healthDetail: healthDetail,
        info: info,
        infoError: infoError,
      );
    });
  } catch (error) {
    return ServiceGuestStatus(
      health: ServiceHealthState.unreachable,
      healthDetail: '$error',
    );
  }
}

/// Polls guest healthcheck + service-info while the instance is running.
final serviceGuestStatusProvider = StreamProvider.autoDispose
    .family<ServiceGuestStatus, String>((ref, instanceName) async* {
  final grpc = ref.watch(grpcClientProvider);

  while (true) {
    final info = ref
        .read(serviceInstanceInfosProvider)
        .where((i) => i.name == instanceName)
        .firstOrNull;
    final status = info?.instanceStatus.status;

    if (status != Status.RUNNING) {
      yield const ServiceGuestStatus(health: ServiceHealthState.unknown);
      await Future<void>.delayed(const Duration(seconds: 3));
      continue;
    }

    final serviceId = info?.info.serviceId ?? '';
    final library = await ref.read(marketplaceLibraryProvider.future);
    final template = library.byId(serviceId);
    final healthPath = template?.healthcheck ?? defaultHealthcheckPath;
    final infoPath = template?.serviceInfo ?? defaultServiceInfoPath;

    yield await fetchServiceGuestStatus(
      grpc: grpc,
      instanceName: instanceName,
      healthcheckPath: healthPath,
      serviceInfoPath: infoPath,
    );

    await Future<void>.delayed(const Duration(seconds: 5));
  }
});
