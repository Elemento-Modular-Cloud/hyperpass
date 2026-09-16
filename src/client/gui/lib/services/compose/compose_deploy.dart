import '../service_library.dart';
import '../service_spec.dart';
import '../service_spec_bind.dart';
import '../service_status.dart';
import 'compose_graph.dart';

enum ComposeDeployNodePhase { pending, launching, waiting, ready, failed }

class ComposeDeployProgress {
  const ComposeDeployProgress({
    required this.phases,
    this.currentRole,
    this.message,
    this.error,
    this.running = false,
    this.finished = false,
  });

  final Map<String, ComposeDeployNodePhase> phases;
  final String? currentRole;
  final String? message;
  final String? error;
  final bool running;
  final bool finished;
}

class ComposeDeployException implements Exception {
  ComposeDeployException(this.message, {this.nodeId});
  final String message;
  final String? nodeId;
  @override
  String toString() => message;
}

/// Hosts used by [deployComposeGraph] so the loop can be tested without gRPC.
class ComposeDeployHost {
  const ComposeDeployHost({
    required this.intentExists,
    required this.createIntent,
    required this.addMember,
    required this.existingRoles,
    required this.waitForReady,
    required this.bindInstance,
  });

  final bool Function(String intentName) intentExists;
  final Future<void> Function(String intentName) createIntent;
  final Future<void> Function({
    required String intentName,
    required ComposeNode node,
    required MarketplaceService? service,
    required Map<String, String> variables,
  }) addMember;
  final Set<String> Function(String intentName) existingRoles;
  final Future<ServiceInfoDocument?> Function({
    required ComposeNode node,
    required String instanceName,
    required MarketplaceService? service,
  }) waitForReady;
  final void Function(String instanceName, String serviceId) bindInstance;
}

/// Sequential intent create/add with contract binding between members.
Future<void> deployComposeGraph({
  required ComposeGraph graph,
  required MarketplaceLibrary library,
  required ComposeDeployHost host,
  required void Function(ComposeDeployProgress progress) onProgress,
}) async {
  final issues = validateComposeGraph(graph, library);
  if (issues.isNotEmpty) {
    throw ComposeDeployException(issues.first.message);
  }
  final ordered = topoSort(graph);
  if (ordered == null) {
    throw ComposeDeployException('Graph has a cycle');
  }

  final intentName = graph.intentName.trim();
  final phases = {
    for (final node in ordered) node.id: ComposeDeployNodePhase.pending,
  };
  void emit({
    String? role,
    String? message,
    String? error,
    bool running = true,
    bool finished = false,
  }) {
    onProgress(ComposeDeployProgress(
      phases: Map.unmodifiable(phases),
      currentRole: role,
      message: message,
      error: error,
      running: running,
      finished: finished,
    ));
  }

  emit(message: 'Creating composition $intentName');
  if (!host.intentExists(intentName)) {
    await host.createIntent(intentName);
  }

  final producerInfo = <String, ServiceInfoDocument>{};
  final already = host.existingRoles(intentName);

  for (final node in ordered) {
    final service = node.isService ? library.lookup(node.serviceId) : null;
    if (node.isService && service == null) {
      phases[node.id] = ComposeDeployNodePhase.failed;
      emit(
        role: node.role,
        error: 'Unknown service ${node.serviceId}',
        running: false,
        finished: true,
      );
      throw ComposeDeployException(
        'Unknown service ${node.serviceId}',
        nodeId: node.id,
      );
    }

    final variables = Map<String, String>.from(node.manualParams);
    final incomingByContract = <String, List<ComposeEdge>>{};
    for (final edge in graph.edges.where((e) => e.to == node.id)) {
      incomingByContract.putIfAbsent(edge.contract, () => []).add(edge);
    }
    for (final entry in incomingByContract.entries) {
      final sources = <ContractProducer>[];
      for (final edge in entry.value) {
        final producer = graph.nodeById(edge.from);
        final info = producer == null ? null : producerInfo[producer.id];
        if (producer == null || info == null) {
          phases[node.id] = ComposeDeployNodePhase.failed;
          emit(
            role: node.role,
            error: 'Producer ${edge.from} is not ready for ${edge.contract}',
            running: false,
            finished: true,
          );
          throw ComposeDeployException(
            'Producer for ${edge.contract} is not ready',
            nodeId: node.id,
          );
        }
        sources.add(
          ContractProducer(
            spec: specForNode(producer, library),
            serviceInfo: info.raw,
          ),
        );
      }
      if (service == null) continue;
      try {
        final bound = bindContracts(
          producers: sources,
          consumer: specForNode(node, library),
          contractId: entry.key,
        );
        if (entry.key == openaiCompatibleContract &&
            incomingByContract.containsKey(caddyCaContract)) {
          bound.remove('ca_url');
          bound.remove('ca_urls');
        }
        variables.addAll(bound);
      } catch (error) {
        phases[node.id] = ComposeDeployNodePhase.failed;
        emit(
          role: node.role,
          error: '$error',
          running: false,
          finished: true,
        );
        throw ComposeDeployException('$error', nodeId: node.id);
      }
    }

    final instanceName = intentMemberInstanceName(intentName, node.role);
    try {
      if (!already.contains(node.role)) {
        phases[node.id] = ComposeDeployNodePhase.launching;
        emit(role: node.role, message: 'Launching ${node.role}');
        await host.addMember(
          intentName: intentName,
          node: node,
          service: service,
          variables: variables,
        );
      }
      phases[node.id] = ComposeDeployNodePhase.waiting;
      emit(
          role: node.role, message: 'Waiting for ${node.role} to become ready');
      final info = await host.waitForReady(
        node: node,
        instanceName: instanceName,
        service: service,
      );
      if (info != null) producerInfo[node.id] = info;
      if (service != null) {
        host.bindInstance(instanceName, service.id);
      }
      phases[node.id] = ComposeDeployNodePhase.ready;
      emit(role: node.role, message: '${node.role} is ready');
    } catch (error) {
      phases[node.id] = ComposeDeployNodePhase.failed;
      emit(
        role: node.role,
        error: '$error',
        running: false,
        finished: true,
      );
      throw ComposeDeployException('$error', nodeId: node.id);
    }
  }

  emit(message: 'Composition $intentName is ready', running: false, finished: true);
}
