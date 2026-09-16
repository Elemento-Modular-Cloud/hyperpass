import '../../llm/llm_id.dart';
import '../service_library.dart';
import '../service_spec.dart';

enum ComposeNodeKind {
  service,
  vm,
  llm;

  static ComposeNodeKind parse(String? raw) {
    return switch (raw) {
      'vm' => ComposeNodeKind.vm,
      'llm' => ComposeNodeKind.llm,
      _ => ComposeNodeKind.service,
    };
  }
}

/// One member on the compose canvas (marketplace service, VM image, or LLM).
class ComposeNode {
  const ComposeNode({
    required this.id,
    required this.role,
    required this.serviceId,
    required this.x,
    required this.y,
    this.kind = ComposeNodeKind.service,
    this.image = '',
    this.modelId = '',
    this.quant = '',
    this.runtime = '',
    this.ctxSize = 0,
    this.maxTokens = 0,
    this.label = '',
    this.manualParams = const {},
  });

  final String id;

  /// Intent member role; the daemon names the instance `{intent}-{role}`.
  final String role;

  /// Catalog id (service), image alias (VM), or model id (LLM).
  final String serviceId;
  final ComposeNodeKind kind;
  final String image;
  final String modelId;
  final String quant;
  final String runtime;
  final int ctxSize;
  final int maxTokens;
  final String label;
  final double x;
  final double y;

  /// Unbound inputs the user typed (not filled by an edge).
  final Map<String, String> manualParams;

  bool get isService => kind == ComposeNodeKind.service;

  String get displayLabel {
    if (label.isNotEmpty) return label;
    if (kind == ComposeNodeKind.llm && modelId.isNotEmpty) return modelId;
    if (kind == ComposeNodeKind.vm && image.isNotEmpty) return image;
    return serviceId;
  }

  ComposeNode copyWith({
    String? id,
    String? role,
    String? serviceId,
    ComposeNodeKind? kind,
    String? image,
    String? modelId,
    String? quant,
    String? runtime,
    int? ctxSize,
    int? maxTokens,
    String? label,
    double? x,
    double? y,
    Map<String, String>? manualParams,
  }) {
    return ComposeNode(
      id: id ?? this.id,
      role: role ?? this.role,
      serviceId: serviceId ?? this.serviceId,
      kind: kind ?? this.kind,
      image: image ?? this.image,
      modelId: modelId ?? this.modelId,
      quant: quant ?? this.quant,
      runtime: runtime ?? this.runtime,
      ctxSize: ctxSize ?? this.ctxSize,
      maxTokens: maxTokens ?? this.maxTokens,
      label: label ?? this.label,
      x: x ?? this.x,
      y: y ?? this.y,
      manualParams: manualParams ?? this.manualParams,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role,
        'serviceId': serviceId,
        'kind': kind.name,
        'image': image,
        'modelId': modelId,
        'quant': quant,
        'runtime': runtime,
        'ctxSize': ctxSize,
        'maxTokens': maxTokens,
        'label': label,
        'x': x,
        'y': y,
        'manualParams': manualParams,
      };

  factory ComposeNode.fromJson(Map<String, Object?> json) {
    final paramsRaw = json['manualParams'];
    final params = <String, String>{};
    if (paramsRaw is Map) {
      for (final entry in paramsRaw.entries) {
        params['${entry.key}'] = '${entry.value}';
      }
    }
    return ComposeNode(
      id: '${json['id']}',
      role: '${json['role']}',
      serviceId: '${json['serviceId']}',
      kind: ComposeNodeKind.parse(json['kind'] as String?),
      image: '${json['image'] ?? ''}',
      modelId: '${json['modelId'] ?? ''}',
      quant: '${json['quant'] ?? ''}',
      runtime: '${json['runtime'] ?? ''}',
      ctxSize: (json['ctxSize'] as num?)?.toInt() ?? 0,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 0,
      label: '${json['label'] ?? ''}',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      manualParams: params,
    );
  }
}

/// A typed contract wire from a producer node to a consumer node.
class ComposeEdge {
  const ComposeEdge({
    required this.from,
    required this.to,
    required this.contract,
  });

  final String from;
  final String to;
  final String contract;

  Map<String, Object?> toJson() => {
        'from': from,
        'to': to,
        'contract': contract,
      };

  factory ComposeEdge.fromJson(Map<String, Object?> json) {
    return ComposeEdge(
      from: '${json['from']}',
      to: '${json['to']}',
      contract: '${json['contract']}',
    );
  }
}

class ComposeIssue {
  const ComposeIssue({
    required this.message,
    this.nodeId,
    this.code = 'invalid',
  });

  final String message;
  final String? nodeId;
  final String code;
}

/// GUI document: canvas layout + contract edges, keyed by [intentName].
class ComposeGraph {
  const ComposeGraph({
    required this.intentName,
    this.nodes = const [],
    this.edges = const [],
  });

  final String intentName;
  final List<ComposeNode> nodes;
  final List<ComposeEdge> edges;

  ComposeNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  ComposeGraph copyWith({
    String? intentName,
    List<ComposeNode>? nodes,
    List<ComposeEdge>? edges,
  }) {
    return ComposeGraph(
      intentName: intentName ?? this.intentName,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
    );
  }

  Map<String, Object?> toJson() => {
        'intentName': intentName,
        'nodes': [for (final node in nodes) node.toJson()],
        'edges': [for (final edge in edges) edge.toJson()],
      };

  factory ComposeGraph.fromJson(Map<String, Object?> json) {
    final nodesRaw = json['nodes'];
    final edgesRaw = json['edges'];
    return ComposeGraph(
      intentName: '${json['intentName'] ?? ''}',
      nodes: [
        if (nodesRaw is List)
          for (final item in nodesRaw)
            if (item is Map)
              ComposeNode.fromJson(
                item.map((k, v) => MapEntry('$k', v as Object?)),
              ),
      ],
      edges: [
        if (edgesRaw is List)
          for (final item in edgesRaw)
            if (item is Map)
              ComposeEdge.fromJson(
                item.map((k, v) => MapEntry('$k', v as Object?)),
              ),
      ],
    );
  }
}

/// Hostname-safe unique intent role derived from a catalog id.
String suggestComposeRole(String serviceId, Iterable<String> taken) {
  var base = serviceFamily(serviceId).replaceAll('_', '-');
  if (base.isEmpty) base = 'service';
  base = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]+'), '-');
  base = base.replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.isEmpty) base = 'service';

  if (!taken.contains(base)) return base;
  for (var i = 2; i < 1000; i++) {
    final candidate = '$base-$i';
    if (!taken.contains(candidate)) return candidate;
  }
  return '$base-${taken.length + 1}';
}

/// Instance name the daemon assigns to an intent member.
String intentMemberInstanceName(String intentName, String role) =>
    '$intentName-$role';

ServiceSpec specForNode(ComposeNode node, MarketplaceLibrary library) {
  if (node.kind == ComposeNodeKind.llm) {
    return ServiceSpec.openaiCompatibleProvider(
      node.modelId.isEmpty ? node.serviceId : node.modelId,
    );
  }
  if (node.kind == ComposeNodeKind.vm) {
    return ServiceSpec.fromInputNames(node.serviceId, const {});
  }
  final service = library.lookup(node.serviceId);
  if (service == null) {
    return ServiceSpec.fromInputNames(node.serviceId, const {});
  }
  return service.composeSpec;
}

/// Input contracts on the left of a node, declaration order.
List<String> composeInputContracts(ServiceSpec spec) =>
    spec.requires.keys.toList();

/// Output contracts on the right. Fan-out sockets (OpenAI, Caddy CA, …) stay
/// independently wireable to many consumers.
List<String> composeOutputContracts(ServiceSpec spec) =>
    spec.provides.keys.toList();

const _httpOutputTypes = {'url', 'ca_url'};

/// HTTP URL outputs that are not already exposed as a `provides` contract pin.
List<ServiceSpecOutput> composeHttpOutputs(ServiceSpec spec) {
  final claimed = <String>{
    for (final provides in spec.provides.values) ...provides.outputs.values,
  };
  return [
    for (final output in spec.outputs.values)
      if (_httpOutputTypes.contains(output.type) &&
          !claimed.contains(output.pointer))
        output,
  ];
}

String composeHttpOutputLabel(ServiceSpecOutput output) {
  final description = output.description?.trim();
  if (description != null && description.isNotEmpty) return description;
  final parts =
      output.pointer.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return output.pointer;
  return parts.last.replaceAll('_', ' ');
}

int composeOutputRowCount(ServiceSpec spec) =>
    composeOutputContracts(spec).length + composeHttpOutputs(spec).length;

String composePinLabel(String contract) {
  return switch (contract) {
    openaiCompatibleContract => 'OpenAI',
    caddyCaContract => 'Caddy CA',
    'n8n_sandbox' => 'n8n sandbox',
    _ => contract,
  };
}

/// Dedicated issuer (`caddy_ca_v1`): provides the contract and does not consume it.
bool isCaddyCaIssuer(ServiceSpec spec) {
  return spec.provides.containsKey(caddyCaContract) &&
      !spec.requires.containsKey(caddyCaContract);
}

/// Output pins have no outgoing cap: one producer can wire the same contract
/// to many consumers (Qdrant, n8n sandbox, OpenAI, Caddy CA, …).
bool composeOutputFansOut(String contract) {
  assert(contract.isNotEmpty);
  return true;
}

/// Input pins that accept more than one producer (Open WebUI / LiteLLM OpenAI).
bool composeInputFansIn(ServiceSpec spec, String contract) {
  final req = spec.requires[contract];
  return req != null && allowsManyIncoming(req);
}

Map<String, Object?> localLlmServiceInfoRaw(ComposeNode node) {
  final model = node.modelId.isEmpty ? node.serviceId : node.modelId;
  return {
    'api_version': 'elemento.service_info/v1',
    'service': model,
    'status': 'ready',
    'endpoints': {'api': openaiVmBaseUrl},
    'credentials': {
      'tokens': ['local'],
    },
    'model': model,
  };
}

/// Inputs the inspector can edit. Generated secrets are filled at boot.
Iterable<ServiceSpecInput> composeManualInputs(ServiceSpec spec) {
  return spec.inputs.values.where((input) => !input.generated);
}

/// Shown after labels that the user must fill or wire.
const composeRequiredMark = '*';

String composeRequiredLabel(String label, {required bool required}) {
  if (!required) return label;
  return '$label $composeRequiredMark';
}

/// A consume pin that must be wired (`min` ≥ 1).
bool composeContractRequired(ServiceSpec spec, String contract) {
  final req = spec.requires[contract];
  return req != null && req.min > 0;
}

/// A typed input that must be set: declared `required`, or pulled in by a
/// group whose `when` field is already bound.
bool composeManualInputRequired(
  ServiceSpec spec,
  ServiceSpecInput input, {
  required Set<String> bound,
}) {
  if (input.required) return true;
  for (final group in spec.groups) {
    if (!bound.contains(group.when)) continue;
    if (group.require.contains(input.name)) return true;
  }
  return false;
}

/// Inputs filled by incoming edges on [nodeId].
Set<String> boundInputNames(
  ComposeGraph graph,
  String nodeId,
  MarketplaceLibrary library,
) {
  final node = graph.nodeById(nodeId);
  if (node == null) return {};
  final spec = specForNode(node, library);
  final names = <String>{};
  for (final edge in graph.edges) {
    if (edge.to != nodeId) continue;
    final required = spec.requires[edge.contract];
    if (required == null) continue;
    names.addAll(required.inputs.values);
  }
  return names;
}

List<ComposeIssue> validateComposeGraph(
  ComposeGraph graph,
  MarketplaceLibrary library,
) {
  final issues = <ComposeIssue>[];
  if (graph.intentName.trim().isEmpty) {
    issues.add(const ComposeIssue(
      message: 'Composition name is required',
      code: 'intent_name',
    ));
  }

  final roles = <String, String>{};
  for (final node in graph.nodes) {
    if (node.role.trim().isEmpty) {
      issues.add(ComposeIssue(
        message: 'Every node needs a role',
        nodeId: node.id,
        code: 'role',
      ));
    } else if (roles.containsKey(node.role)) {
      issues.add(ComposeIssue(
        message: 'Role "${node.role}" is used more than once',
        nodeId: node.id,
        code: 'role_duplicate',
      ));
    } else {
      roles[node.role] = node.id;
    }

    if (node.isService && library.lookup(node.serviceId) == null) {
      issues.add(ComposeIssue(
        message: 'Unknown service "${node.serviceId}"',
        nodeId: node.id,
        code: 'unknown_service',
      ));
    }
    if (node.kind == ComposeNodeKind.vm && node.image.trim().isEmpty) {
      issues.add(ComposeIssue(
        message: '${node.role} is missing a VM image',
        nodeId: node.id,
        code: 'vm_image',
      ));
    }
    if (node.kind == ComposeNodeKind.llm && node.modelId.trim().isEmpty) {
      issues.add(ComposeIssue(
        message: '${node.role} is missing a model id',
        nodeId: node.id,
        code: 'llm_model',
      ));
    }
  }

  final nodeIds = {for (final node in graph.nodes) node.id};
  final incoming = <String, Map<String, int>>{};
  for (final edge in graph.edges) {
    if (!nodeIds.contains(edge.from) || !nodeIds.contains(edge.to)) {
      issues.add(ComposeIssue(
        message: 'Edge ${edge.contract} refers to a missing node',
        code: 'dangling_edge',
      ));
      continue;
    }
    if (edge.from == edge.to) {
      issues.add(ComposeIssue(
        message: 'Cannot connect a node to itself',
        nodeId: edge.to,
        code: 'self_edge',
      ));
      continue;
    }

    final producer = specForNode(graph.nodeById(edge.from)!, library);
    final consumer = specForNode(graph.nodeById(edge.to)!, library);
    if (!producer.provides.containsKey(edge.contract)) {
      issues.add(ComposeIssue(
        message:
            '${graph.nodeById(edge.from)!.role} does not provide ${edge.contract}',
        nodeId: edge.from,
        code: 'missing_provide',
      ));
    }
    if (!consumer.requires.containsKey(edge.contract)) {
      issues.add(ComposeIssue(
        message:
            '${graph.nodeById(edge.to)!.role} does not require ${edge.contract}',
        nodeId: edge.to,
        code: 'missing_require',
      ));
    }

    final seen = incoming.putIfAbsent(edge.to, () => <String, int>{});
    final count = (seen[edge.contract] ?? 0) + 1;
    seen[edge.contract] = count;
    final req = consumer.requires[edge.contract];
    final limit = req == null ? 1 : incomingLimit(req);
    if (limit == 1 && count > 1) {
      issues.add(ComposeIssue(
        message:
            '${graph.nodeById(edge.to)!.role} already has a ${edge.contract} input',
        nodeId: edge.to,
        code: 'duplicate_incoming',
      ));
    } else if (limit != null && count > limit) {
      issues.add(ComposeIssue(
        message:
            '${graph.nodeById(edge.to)!.role} accepts at most $limit ${edge.contract} input(s)',
        nodeId: edge.to,
        code: 'too_many_incoming',
      ));
    }
  }

  if (topoSort(graph) == null &&
      graph.nodes.isNotEmpty &&
      graph.edges.isNotEmpty) {
    issues.add(const ComposeIssue(
      message: 'Graph has a cycle',
      code: 'cycle',
    ));
  }

  for (final node in graph.nodes) {
    final spec = specForNode(node, library);
    final bound = boundInputNames(graph, node.id, library);
    for (final entry in node.manualParams.entries) {
      if (entry.value.trim().isNotEmpty) bound.add(entry.key);
    }
    for (final group in spec.groups) {
      if (!bound.contains(group.when)) continue;
      for (final name in group.require) {
        if (bound.contains(name)) continue;
        issues.add(ComposeIssue(
          message: '${node.role}: ${group.when} requires $name (${group.name})',
          nodeId: node.id,
          code: 'group',
        ));
      }
    }
  }

  final issuers = [
    for (final node in graph.nodes)
      if (isCaddyCaIssuer(specForNode(node, library))) node,
  ];
  if (issuers.isNotEmpty) {
    for (final node in graph.nodes) {
      final spec = specForNode(node, library);
      if (!spec.requires.containsKey(caddyCaContract)) continue;
      final wired = graph.edges.any(
        (edge) => edge.to == node.id && edge.contract == caddyCaContract,
      );
      if (wired) continue;
      issues.add(ComposeIssue(
        message: '${node.role} should take Caddy CA from ${issuers.first.role} '
            '(launch the CA VM first)',
        nodeId: node.id,
        code: 'ca_unwired',
      ));
    }
  }

  return issues;
}

/// Kahn topo-sort. Returns null when the graph has a cycle.
List<ComposeNode>? topoSort(ComposeGraph graph) {
  final byId = {for (final node in graph.nodes) node.id: node};
  final incoming = {for (final node in graph.nodes) node.id: 0};
  final adj = {for (final node in graph.nodes) node.id: <String>[]};
  for (final edge in graph.edges) {
    if (!byId.containsKey(edge.from) || !byId.containsKey(edge.to)) {
      continue;
    }
    adj[edge.from]!.add(edge.to);
    incoming[edge.to] = incoming[edge.to]! + 1;
  }

  final queue = [
    for (final node in graph.nodes)
      if (incoming[node.id] == 0) node.id,
  ];
  final ordered = <ComposeNode>[];
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    ordered.add(byId[id]!);
    for (final next in adj[id]!) {
      incoming[next] = incoming[next]! - 1;
      if (incoming[next] == 0) queue.add(next);
    }
  }
  if (ordered.length != graph.nodes.length) return null;
  return ordered;
}

bool canConnect({
  required ComposeGraph graph,
  required MarketplaceLibrary library,
  required String fromId,
  required String toId,
  required String contract,
}) {
  if (fromId == toId) return false;
  final from = graph.nodeById(fromId);
  final to = graph.nodeById(toId);
  if (from == null || to == null) return false;
  final producer = specForNode(from, library);
  final consumer = specForNode(to, library);
  if (!producer.provides.containsKey(contract)) return false;
  final req = consumer.requires[contract];
  if (req == null) return false;
  if (graph.edges.any(
    (e) => e.from == fromId && e.to == toId && e.contract == contract,
  )) {
    return false;
  }
  final incoming =
      graph.edges.where((e) => e.to == toId && e.contract == contract).length;
  final limit = incomingLimit(req);
  if (limit != null && incoming >= limit) return false;
  return true;
}

/// Extra `caddy_ca` edge when wiring an HTTPS peer, from the canvas issuer.
ComposeEdge? companionCaddyCaEdge({
  required ComposeGraph graph,
  required MarketplaceLibrary library,
  required ComposeEdge edge,
}) {
  if (edge.contract == caddyCaContract) return null;
  for (final node in graph.nodes) {
    if (node.id == edge.to) continue;
    if (!isCaddyCaIssuer(specForNode(node, library))) continue;
    if (!canConnect(
      graph: graph,
      library: library,
      fromId: node.id,
      toId: edge.to,
      contract: caddyCaContract,
    )) {
      continue;
    }
    return ComposeEdge(
      from: node.id,
      to: edge.to,
      contract: caddyCaContract,
    );
  }
  return null;
}
