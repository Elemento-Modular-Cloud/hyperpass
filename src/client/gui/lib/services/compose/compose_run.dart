import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:convert';

import '../../llm/llm_features.dart';
import '../../llm/providers.dart';
import '../../providers.dart';
import '../../cloud_init/cloud_init_store.dart';
import '../gateway_ca.dart';
import '../service_intent_member.dart';
import '../service_library.dart';
import '../service_status.dart';
import 'compose_deploy.dart';
import 'compose_graph.dart';

const composeReadyTimeout = Duration(minutes: 20);
const composeReadyPoll = Duration(seconds: 4);

const _inferenceBackendIds = {
  'llamacpp',
  if (enableMlxBackend) 'mlx',
};

Future<void> ensureComposeIntent({
  required bool daemonAvailable,
  required List<IntentInfo> intents,
  required GrpcClient grpc,
  required String name,
  required void Function() invalidateIntents,
}) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty || !daemonAvailable) return;
  if (intents.any((intent) => intent.name == trimmed)) return;
  await grpc.intentCreate(IntentCreateRequest(name: trimmed));
  invalidateIntents();
}

ComposeDeployHost composeDeployHostFor(Ref ref) {
  final grpc = ref.read(grpcClientProvider);
  return ComposeDeployHost(
    intentExists: (name) {
      final intents = ref.read(intentsStreamProvider).asData?.value ?? const [];
      return intents.any((intent) => intent.name == name);
    },
    createIntent: (name) async {
      await grpc.intentCreate(IntentCreateRequest(name: name));
      ref.invalidate(intentsStreamProvider);
    },
    existingRoles: (name) {
      final intents = ref.read(intentsStreamProvider).asData?.value ?? const [];
      for (final intent in intents) {
        if (intent.name != name) continue;
        return {for (final member in intent.members) member.role};
      }
      return {};
    },
    addMember: ({
      required String intentName,
      required ComposeNode node,
      required MarketplaceService? service,
      required Map<String, String> variables,
    }) async {
      String? pem;
      try {
        pem = await fetchGatewayCaPem();
      } catch (_) {
        pem = null;
      }
      String llmRuntime = node.runtime;
      if (node.kind == ComposeNodeKind.llm) {
        llmRuntime = await _composeLlmRuntime(ref, composeResolvedRuntime(node));
      }
      String? cloudInit;
      if (node.kind == ComposeNodeKind.vm && node.cloudInitName.isNotEmpty) {
        try {
          final store = await ref.read(cloudInitStoreProvider.future);
          cloudInit = await store.read(node.cloudInitName);
        } catch (_) {
          throw ComposeDeployException(
            'Cloud-init "${node.cloudInitName}" could not be read',
          );
        }
      }
      final member = switch (node.kind) {
        ComposeNodeKind.service => buildServiceIntentMember(
            service: service!,
            role: node.role,
            variables: variables,
            gatewayCaPem: pem,
            numCores: composeResolvedCpus(node, service),
            memSize: '${composeResolvedMemBytes(node, service)}B',
            diskSpace: '${composeResolvedDiskBytes(node, service)}B',
          ),
        ComposeNodeKind.vm => IntentMemberRequest(
            role: node.role,
            image: node.image,
            numCores: composeResolvedCpus(node),
            memSize: '${composeResolvedMemBytes(node)}B',
            diskSpace: '${composeResolvedDiskBytes(node)}B',
            cloudInitUserData: cloudInit ?? '',
          ),
        ComposeNodeKind.llm => IntentMemberRequest(
            role: node.role,
            modelId: node.modelId,
            quant: node.quant,
            runtime: llmRuntime,
            ctxSize: composeResolvedCtxSize(node),
            maxTokens: node.maxTokens,
          ),
      };
      await grpc.intentAddMember(
        IntentAddMemberRequest(name: intentName, members: [member]),
      );
      ref.invalidate(intentsStreamProvider);
    },
    waitForReady: ({
      required ComposeNode node,
      required String instanceName,
      required MarketplaceService? service,
    }) async {
      if (node.kind == ComposeNodeKind.llm) {
        return ServiceInfoDocument.parse(
          jsonEncode(localLlmServiceInfoRaw(node)),
        );
      }
      if (node.kind == ComposeNodeKind.vm) {
        await waitForComposeVmRunning(
          ref: ref,
          instanceName: instanceName,
        );
        return null;
      }
      return waitForComposeMemberReady(
        ref: ref,
        grpc: grpc,
        instanceName: instanceName,
        service: service!,
      );
    },
    bindInstance: (instanceName, serviceId) {
      ref
          .read(serviceInstanceBindingsProvider.notifier)
          .bind(instanceName, serviceId);
    },
  );
}

Future<ServiceInfoDocument> waitForComposeMemberReady({
  required Ref ref,
  required GrpcClient grpc,
  required String instanceName,
  required MarketplaceService service,
  Duration timeout = composeReadyTimeout,
  Duration poll = composeReadyPoll,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      await ref.read(allVmInfosProvider.notifier).update();
    } catch (_) {}
    final running = ref.read(allActiveVmInfosProvider).any(
          (vm) =>
              vm.name == instanceName &&
              vm.instanceStatus.status == Status.RUNNING,
        );
    if (running) {
      final status = await fetchServiceGuestStatus(
        grpc: grpc,
        instanceName: instanceName,
        healthcheckPath: service.healthcheck ?? defaultHealthcheckPath,
        serviceInfoPath: service.serviceInfo ?? defaultServiceInfoPath,
      );
      if (status.health == ServiceHealthState.healthy && status.info != null) {
        return status.info!;
      }
    }
    await Future<void>.delayed(poll);
  }
  throw ComposeDeployException(
    'Timed out waiting for $instanceName to become ready',
  );
}

Future<void> waitForComposeVmRunning({
  required Ref ref,
  required String instanceName,
  Duration timeout = composeReadyTimeout,
  Duration poll = composeReadyPoll,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      await ref.read(allVmInfosProvider.notifier).update();
    } catch (_) {}
    final running = ref.read(allActiveVmInfosProvider).any(
          (vm) =>
              vm.name == instanceName &&
              vm.instanceStatus.status == Status.RUNNING,
        );
    if (running) return;
    await Future<void>.delayed(poll);
  }
  throw ComposeDeployException(
    'Timed out waiting for $instanceName to become ready',
  );
}

class ComposeDeployNotifier extends Notifier<ComposeDeployProgress?> {
  @override
  ComposeDeployProgress? build() => null;

  Future<void> deploy({
    required ComposeGraph graph,
    required MarketplaceLibrary library,
  }) async {
    try {
      await deployComposeGraph(
        graph: graph,
        library: library,
        host: composeDeployHostFor(ref),
        onProgress: (progress) => state = progress,
      );
    } on ComposeDeployException catch (error) {
      state = ComposeDeployProgress(
        phases: state?.phases ?? const {},
        currentRole: state?.currentRole,
        error: error.message,
        running: false,
        finished: true,
      );
      rethrow;
    }
  }
}

final composeDeployProvider =
    NotifierProvider<ComposeDeployNotifier, ComposeDeployProgress?>(
  ComposeDeployNotifier.new,
);

Future<String> _composeLlmRuntime(Ref ref, String preferred) async {
  try {
    final backends = await ref.read(llmBackendsProvider.future);
    final ready = [
      for (final backend in backends.backends)
        if (backend.status == 'ready' &&
            _inferenceBackendIds.contains(backend.id))
          backend.id,
    ];
    if (preferred.isNotEmpty && ready.contains(preferred)) return preferred;
    return ready.isEmpty ? preferred : ready.first;
  } catch (_) {
    return preferred;
  }
}
