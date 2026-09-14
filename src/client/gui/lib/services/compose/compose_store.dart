import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers.dart';
import '../service_library.dart';
import 'compose_graph.dart';

const composeGraphsPrefsKey = 'local.compose-graphs';
const composeCurrentIntentPrefsKey = 'local.compose-current-intent';

Map<String, ComposeGraph> loadComposeGraphs(SharedPreferences prefs) {
  final raw = prefs.getString(composeGraphsPrefsKey);
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final graphs = <String, ComposeGraph>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final graph = ComposeGraph.fromJson(
        value.map((k, v) => MapEntry('$k', v as Object?)),
      );
      graphs['${entry.key}'] = graph;
    }
    return graphs;
  } catch (_) {
    return {};
  }
}

void saveComposeGraphs(
  SharedPreferences prefs,
  Map<String, ComposeGraph> graphs,
) {
  prefs.setString(
    composeGraphsPrefsKey,
    jsonEncode({
      for (final entry in graphs.entries) entry.key: entry.value.toJson(),
    }),
  );
}

class ComposeEditorState {
  const ComposeEditorState({
    required this.graph,
    this.selectedNodeIds = const {},
  });

  final ComposeGraph graph;
  final Set<String> selectedNodeIds;

  String? get selectedNodeId =>
      selectedNodeIds.isEmpty ? null : selectedNodeIds.first;

  ComposeEditorState copyWith({
    ComposeGraph? graph,
    Set<String>? selectedNodeIds,
    bool clearSelection = false,
  }) {
    return ComposeEditorState(
      graph: graph ?? this.graph,
      selectedNodeIds: clearSelection
          ? const {}
          : (selectedNodeIds ?? this.selectedNodeIds),
    );
  }
}

class ComposeEditorNotifier extends Notifier<ComposeEditorState> {
  var _nextId = 0;

  @override
  ComposeEditorState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final graphs = loadComposeGraphs(prefs);
    final current = prefs.getString(composeCurrentIntentPrefsKey) ?? '';
    final graph = graphs[current] ??
        ComposeGraph(intentName: current.isEmpty ? '' : current);
    return ComposeEditorState(graph: graph);
  }

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  String _newNodeId() {
    _nextId += 1;
    return 'n${DateTime.now().microsecondsSinceEpoch}-$_nextId';
  }

  void _persist(ComposeGraph graph) {
    final prefs = _prefs;
    final graphs = loadComposeGraphs(prefs);
    final name = graph.intentName.trim();
    if (name.isEmpty) return;
    graphs[name] = graph;
    prefs.setString(composeCurrentIntentPrefsKey, name);
    saveComposeGraphs(prefs, graphs);
  }

  /// Writes the current graph. No-op until it has an intent name.
  void save() => _persist(state.graph);

  List<String> savedIntentNames() {
    final names = loadComposeGraphs(_prefs).keys.toList()..sort();
    return names;
  }

  void openIntent(String intentName) {
    final prefs = _prefs;
    final graphs = loadComposeGraphs(prefs);
    final graph = graphs[intentName] ?? ComposeGraph(intentName: intentName);
    prefs.setString(composeCurrentIntentPrefsKey, intentName);
    state = ComposeEditorState(graph: graph);
  }

  void newDraft() {
    _prefs.setString(composeCurrentIntentPrefsKey, '');
    state = const ComposeEditorState(graph: ComposeGraph(intentName: ''));
  }

  void setIntentName(String name) {
    final previous = state.graph.intentName.trim();
    final graph = state.graph.copyWith(intentName: name);
    if (previous.isNotEmpty && previous != name.trim()) {
      final prefs = _prefs;
      final graphs = loadComposeGraphs(prefs);
      graphs.remove(previous);
      saveComposeGraphs(prefs, graphs);
    }
    _persist(graph);
    state = state.copyWith(graph: graph);
  }

  void selectNode(String? id, {bool additive = false}) {
    if (id == null) {
      state = state.copyWith(clearSelection: true);
      return;
    }
    if (!additive) {
      state = state.copyWith(selectedNodeIds: {id});
      return;
    }
    final next = {...state.selectedNodeIds};
    if (!next.add(id)) next.remove(id);
    state = state.copyWith(selectedNodeIds: next);
  }

  void selectNodes(Set<String> ids, {bool additive = false}) {
    state = state.copyWith(
      selectedNodeIds: additive ? {...state.selectedNodeIds, ...ids} : {...ids},
    );
  }

  void selectAll() {
    state = state.copyWith(
      selectedNodeIds: {for (final node in state.graph.nodes) node.id},
    );
  }

  void addService(MarketplaceService service, {double? x, double? y}) {
    _addNode(
      ComposeNode(
        id: _newNodeId(),
        role: suggestComposeRole(
            service.id, state.graph.nodes.map((n) => n.role)),
        serviceId: service.id,
        kind: ComposeNodeKind.service,
        label: service.displayName,
        x: x ?? (80.0 + state.graph.nodes.length * 36),
        y: y ?? (80.0 + state.graph.nodes.length * 28),
      ),
    );
  }

  void addVm({
    required String image,
    required String label,
    String? diskSpace,
    double? x,
    double? y,
  }) {
    _addNode(
      ComposeNode(
        id: _newNodeId(),
        role: suggestComposeRole(image, state.graph.nodes.map((n) => n.role)),
        serviceId: image,
        kind: ComposeNodeKind.vm,
        image: image,
        label: label,
        x: x ?? (80.0 + state.graph.nodes.length * 36),
        y: y ?? (80.0 + state.graph.nodes.length * 28),
        manualParams: {
          if (diskSpace != null && diskSpace.isNotEmpty) 'diskSpace': diskSpace,
        },
      ),
    );
  }

  void addLlm({
    required String modelId,
    String label = '',
    String quant = '',
    String runtime = '',
    int ctxSize = 0,
    int maxTokens = 0,
    double? x,
    double? y,
  }) {
    _addNode(
      ComposeNode(
        id: _newNodeId(),
        role: suggestComposeRole(modelId, state.graph.nodes.map((n) => n.role)),
        serviceId: modelId,
        kind: ComposeNodeKind.llm,
        modelId: modelId,
        quant: quant,
        runtime: runtime,
        ctxSize: ctxSize,
        maxTokens: maxTokens,
        label: label.isEmpty ? modelId : label,
        x: x ?? (80.0 + state.graph.nodes.length * 36),
        y: y ?? (80.0 + state.graph.nodes.length * 28),
      ),
    );
  }

  void _addNode(ComposeNode node) {
    if (state.graph.intentName.trim().isEmpty) return;
    final graph = state.graph.copyWith(nodes: [...state.graph.nodes, node]);
    _persist(graph);
    state = state.copyWith(graph: graph, selectedNodeIds: {node.id});
  }

  void moveNode(String id, double x, double y) {
    moveNodes({id: (x, y)});
  }

  void moveNodes(Map<String, (double, double)> positions) {
    if (positions.isEmpty) return;
    final nodes = [
      for (final node in state.graph.nodes)
        if (positions.containsKey(node.id))
          node.copyWith(
            x: positions[node.id]!.$1,
            y: positions[node.id]!.$2,
          )
        else
          node,
    ];
    final graph = state.graph.copyWith(nodes: nodes);
    _persist(graph);
    state = state.copyWith(graph: graph);
  }

  void setRole(String id, String role) {
    final nodes = [
      for (final node in state.graph.nodes)
        if (node.id == id) node.copyWith(role: role.trim()) else node,
    ];
    final graph = state.graph.copyWith(nodes: nodes);
    _persist(graph);
    state = state.copyWith(graph: graph);
  }

  void setManualParam(String id, String name, String value) {
    final nodes = [
      for (final node in state.graph.nodes)
        if (node.id == id)
          node.copyWith(
            manualParams: {
              ...node.manualParams,
              if (value.trim().isEmpty) name: '' else name: value.trim(),
            }..removeWhere((key, val) => val.isEmpty),
          )
        else
          node,
    ];
    final graph = state.graph.copyWith(nodes: nodes);
    _persist(graph);
    state = state.copyWith(graph: graph);
  }

  void removeNode(String id) {
    final graph = state.graph.copyWith(
      nodes: [
        for (final node in state.graph.nodes)
          if (node.id != id) node
      ],
      edges: [
        for (final edge in state.graph.edges)
          if (edge.from != id && edge.to != id) edge,
      ],
    );
    _persist(graph);
    final remaining = {...state.selectedNodeIds}..remove(id);
    state = state.copyWith(graph: graph, selectedNodeIds: remaining);
  }

  void removeSelected() {
    final ids = state.selectedNodeIds;
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      removeNode(ids.first);
      return;
    }
    final graph = state.graph.copyWith(
      nodes: [
        for (final node in state.graph.nodes)
          if (!ids.contains(node.id)) node
      ],
      edges: [
        for (final edge in state.graph.edges)
          if (!ids.contains(edge.from) && !ids.contains(edge.to)) edge,
      ],
    );
    _persist(graph);
    state = state.copyWith(graph: graph, clearSelection: true);
  }

  bool addEdge(ComposeEdge edge, MarketplaceLibrary library) {
    if (!canConnect(
      graph: state.graph,
      library: library,
      fromId: edge.from,
      toId: edge.to,
      contract: edge.contract,
    )) {
      return false;
    }
    var edges = [...state.graph.edges, edge];
    var graph = state.graph.copyWith(edges: edges);
    final companion = companionCaddyCaEdge(
      graph: graph,
      library: library,
      edge: edge,
    );
    if (companion != null) {
      edges = [...edges, companion];
      graph = graph.copyWith(edges: edges);
    }
    _persist(graph);
    state = state.copyWith(graph: graph);
    return true;
  }

  void removeEdge(ComposeEdge edge) {
    final graph = state.graph.copyWith(
      edges: [
        for (final existing in state.graph.edges)
          if (!(existing.from == edge.from &&
              existing.to == edge.to &&
              existing.contract == edge.contract))
            existing,
      ],
    );
    _persist(graph);
    state = state.copyWith(graph: graph);
  }
}

final composeEditorProvider =
    NotifierProvider<ComposeEditorNotifier, ComposeEditorState>(
  ComposeEditorNotifier.new,
);
