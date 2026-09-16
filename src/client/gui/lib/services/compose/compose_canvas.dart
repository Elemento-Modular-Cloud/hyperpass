import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brand.dart';
import '../../distro_branding.dart';
import '../../l10n/app_localizations.dart';
import '../../llm/catalogue/model_branding.dart';
import '../service_branding.dart';
import '../service_library.dart';
import 'compose_graph.dart';
import 'compose_store.dart';
import 'compose_style.dart';

const composeNodeWidth = 228.0;
const composeNodeHeaderHeight = 42.0;
const composePinRowHeight = 22.0;
const composeNodePinsPaddingTop = 4.0;
const composeNodePinsPaddingBottom = 6.0;
const composeNodeFooterHeight = 26.0;
const composePinHitSlop = 10.0;
const composeMinScale = 0.25;
const composeMaxScale = 2.6;
const composeCanvasWidth = 3200.0;
const composeCanvasHeight = 2200.0;

/// Click vs drag threshold. InteractiveViewer uses a 2px mouse slop, which
/// turns ordinary clicks into canvas pans.
const composePointerSlop = kTouchSlop;

class ComposeCanvas extends ConsumerStatefulWidget {
  const ComposeCanvas({required this.library, super.key});

  final MarketplaceLibrary library;

  @override
  ConsumerState<ComposeCanvas> createState() => _ComposeCanvasState();
}

class _ComposeCanvasState extends ConsumerState<ComposeCanvas> {
  final _transform = TransformationController();
  final _viewerKey = GlobalKey();
  String? _dragNodeId;
  Map<String, Offset> _dragNodeStarts = const {};
  Offset? _dragPointerStart;
  Offset? _dragDelta;
  String? _wireFromId;
  String? _wireContract;
  Offset? _wireEnd;
  int? _wirePointer;
  int? _armedPinPointer;
  String? _armedPinNodeId;
  String? _armedPinContract;
  Offset? _armedPinOrigin;
  bool _armedPinIsOutput = false;
  bool _armedPinMoved = false;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  int? _marqueePointer;
  Offset? _backgroundDown;
  int? _canvasPanPointer;
  Offset? _canvasPanLastGlobal;
  bool _canvasPanning = false;
  String? _pressNodeId;
  Offset? _pressOrigin;

  bool get _wiring => _wireFromId != null;
  bool get _dragging => _dragNodeId != null;
  bool get _marquee => _marqueeStart != null;
  bool get _clickWiring => _wiring && _wirePointer == null;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_syncDropOrigin);
    _scheduleFit();
  }

  @override
  void dispose() {
    _transform.removeListener(_syncDropOrigin);
    _transform.dispose();
    super.dispose();
  }

  void _syncDropOrigin() {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final scene = _transform.toScene(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    final next = (
      scene.dx - composeNodeWidth / 2,
      scene.dy - composeNodeHeaderHeight,
    );
    final current = ref.read(composeDropOriginProvider);
    if ((current.$1 - next.$1).abs() < 1 && (current.$2 - next.$2).abs() < 1) {
      return;
    }
    ref.read(composeDropOriginProvider.notifier).set(next);
  }

  Offset _toScene(Offset global) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return _transform.toScene(global);
    }
    return _transform.toScene(box.globalToLocal(global));
  }

  bool get _additiveKeys {
    return HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
  }

  void _clearWire() {
    if (!_wiring) return;
    setState(() {
      _wireFromId = null;
      _wireContract = null;
      _wireEnd = null;
      _wirePointer = null;
    });
  }

  void _beginWire(String nodeId, String contract, Offset global,
      [int? pointer]) {
    setState(() {
      _wireFromId = nodeId;
      _wireContract = contract;
      _wireEnd = _toScene(global);
      _wirePointer = pointer;
      _marqueeStart = null;
      _marqueeEnd = null;
      _marqueePointer = null;
    });
  }

  void _updateWire(Offset global) {
    if (!_wiring) return;
    setState(() => _wireEnd = _toScene(global));
  }

  void _tryCompleteWire(Offset global) {
    if (!_wiring) return;
    final fromId = _wireFromId;
    final contract = _wireContract;
    if (fromId == null || contract == null) return;
    final target = _hitInputPin(
      ref.read(composeEditorProvider).graph,
      _toScene(global),
      contract,
    );
    if (target == null) return;
    _commitEdge(fromId, target, contract);
  }

  void _tapOutputPin(String nodeId, String contract, Offset global) {
    if (_wireFromId == nodeId && _wireContract == contract) {
      _clearWire();
      return;
    }
    _beginWire(nodeId, contract, global);
  }

  void _tapInputPin(String nodeId, String contract) {
    final fromId = _wireFromId;
    final wireContract = _wireContract;
    if (fromId == null || wireContract == null) return;
    if (wireContract != contract) return;
    _commitEdge(fromId, nodeId, contract);
  }

  void _onWirePointerDown(PointerDownEvent event) {
    if (!_clickWiring) return;
    _updateWire(event.position);
    final graph = ref.read(composeEditorProvider).graph;
    final contract = _wireContract;
    if (contract == null) return;
    final scene = _toScene(event.position);
    if (_hitInputPin(graph, scene, contract) != null) return;
    if (_hitOutputPin(graph, scene) != null) return;
    _clearWire();
  }

  void _armPin({
    required int pointer,
    required String nodeId,
    required String contract,
    required Offset origin,
    required bool output,
  }) {
    _armedPinPointer = pointer;
    _armedPinNodeId = nodeId;
    _armedPinContract = contract;
    _armedPinOrigin = origin;
    _armedPinIsOutput = output;
    _armedPinMoved = false;
    setState(() {});
  }

  void _clearArmedPin() {
    _armedPinPointer = null;
    _armedPinNodeId = null;
    _armedPinContract = null;
    _armedPinOrigin = null;
    _armedPinIsOutput = false;
    _armedPinMoved = false;
  }

  void _onOutputPinDown(
    String nodeId,
    String contract,
    Offset global,
    int pointer,
  ) {
    _armPin(
      pointer: pointer,
      nodeId: nodeId,
      contract: contract,
      origin: global,
      output: true,
    );
  }

  void _onOutputPinMove(Offset global, int pointer) {
    if (_armedPinPointer != pointer || !_armedPinIsOutput) return;
    final nodeId = _armedPinNodeId;
    final contract = _armedPinContract;
    if (nodeId == null || contract == null) return;
    if (_wiring && _wirePointer == pointer) {
      _updateWire(global);
      return;
    }
    final origin = _armedPinOrigin;
    if (origin == null) return;
    if ((global - origin).distance > composePointerSlop) {
      _armedPinMoved = true;
      _beginWire(nodeId, contract, global, pointer);
    }
  }

  void _onOutputPinUp(Offset global, int pointer) {
    if (_armedPinPointer != pointer || !_armedPinIsOutput) return;
    final nodeId = _armedPinNodeId;
    final contract = _armedPinContract;
    final moved = _armedPinMoved;
    _clearArmedPin();
    if (nodeId == null || contract == null) {
      setState(() {});
      return;
    }
    if (moved) {
      _tryCompleteWire(global);
      if (_wiring && _wirePointer == pointer) _clearWire();
      setState(() {});
      return;
    }
    _tapOutputPin(nodeId, contract, global);
  }

  void _onInputPinDown(
    String nodeId,
    String contract,
    Offset global,
    int pointer,
  ) {
    _armPin(
      pointer: pointer,
      nodeId: nodeId,
      contract: contract,
      origin: global,
      output: false,
    );
  }

  void _onInputPinUp(String nodeId, String contract, int pointer) {
    if (_armedPinPointer != pointer || _armedPinIsOutput) return;
    final moved = _armedPinMoved;
    _clearArmedPin();
    if (!moved) _tapInputPin(nodeId, contract);
    setState(() {});
  }

  void _onCardPointerDown(ComposeNode node, Offset origin) {
    if (_armedPinPointer != null) return;
    _pressNodeId = node.id;
    _pressOrigin = origin;
  }

  void _onCardPointerMove(ComposeNode node, Offset global) {
    if (_armedPinPointer != null) return;
    if (_dragNodeId == node.id) {
      _updateNodeDrag(node.id, global);
      return;
    }
    if (_pressNodeId != node.id || _pressOrigin == null) return;
    if ((global - _pressOrigin!).distance <= composePointerSlop) return;
    _startNodeDrag(node, _pressOrigin!);
    _updateNodeDrag(node.id, global);
  }

  void _onCardPointerUp(ComposeNode node) {
    _endNodeDrag(node.id);
    _pressNodeId = null;
    _pressOrigin = null;
  }

  void _startNodeDrag(ComposeNode node, Offset origin) {
    if (_armedPinPointer != null) return;
    final editor = ref.read(composeEditorProvider);
    final notifier = ref.read(composeEditorProvider.notifier);
    if (!editor.selectedNodeIds.contains(node.id)) {
      notifier.selectNode(node.id);
    }
    final selected = {
      ...ref.read(composeEditorProvider).selectedNodeIds,
      node.id,
    };
    setState(() {
      _wireFromId = null;
      _wireContract = null;
      _wireEnd = null;
      _wirePointer = null;
      _dragNodeId = node.id;
      _dragPointerStart = origin;
      _dragDelta = Offset.zero;
      _dragNodeStarts = {
        for (final item in editor.graph.nodes)
          if (selected.contains(item.id)) item.id: Offset(item.x, item.y),
      };
    });
  }

  void _updateNodeDrag(String nodeId, Offset global) {
    if (_armedPinPointer != null) return;
    if (_dragNodeId != nodeId ||
        _dragPointerStart == null ||
        _dragNodeStarts.isEmpty) {
      return;
    }
    setState(() {
      _dragDelta = _toScene(global) - _toScene(_dragPointerStart!);
    });
  }

  void _endNodeDrag(String nodeId) {
    if (_dragNodeId != nodeId) return;
    final delta = _dragDelta;
    final starts = Map<String, Offset>.from(_dragNodeStarts);
    setState(() {
      _dragNodeId = null;
      _dragNodeStarts = const {};
      _dragPointerStart = null;
      _dragDelta = null;
    });
    if (delta == null || starts.isEmpty || delta.distance < 0.5) return;
    ref.read(composeEditorProvider.notifier).moveNodes({
      for (final entry in starts.entries)
        entry.key: (entry.value.dx + delta.dx, entry.value.dy + delta.dy),
    });
  }

  ComposeGraph _displayGraph(ComposeGraph graph) {
    final delta = _dragDelta;
    if (delta == null || _dragNodeStarts.isEmpty) return graph;
    return graph.copyWith(
      nodes: [
        for (final node in graph.nodes)
          if (_dragNodeStarts.containsKey(node.id))
            node.copyWith(
              x: _dragNodeStarts[node.id]!.dx + delta.dx,
              y: _dragNodeStarts[node.id]!.dy + delta.dy,
            )
          else
            node,
      ],
    );
  }

  void _panViewer(Offset fromGlobal, Offset toGlobal) {
    final from = _toScene(fromGlobal);
    final to = _toScene(toGlobal);
    final delta = to - from;
    if (delta == Offset.zero) return;
    _transform.value = _transform.value.clone()
      ..translateByDouble(delta.dx, delta.dy, 0, 1);
  }

  void _onTrackpadScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.kind != PointerDeviceKind.trackpad) return;
    if (_wiring || _dragging || _marquee) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      final scroll = signal as PointerScrollEvent;
      final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final local = box.globalToLocal(scroll.position);
      final localDelta = PointerEvent.transformDeltaViaPositions(
        untransformedEndPosition: scroll.position + scroll.scrollDelta,
        untransformedDelta: scroll.scrollDelta,
        transform: scroll.transform,
      );
      final from = _transform.toScene(local);
      final to = _transform.toScene(local - localDelta);
      final delta = to - from;
      if (delta == Offset.zero) return;
      _transform.value = _transform.value.clone()
        ..translateByDouble(delta.dx, delta.dy, 0, 1);
    });
  }

  void _commitEdge(String fromId, String toId, String contract) {
    ref.read(composeEditorProvider.notifier).addEdge(
          ComposeEdge(from: fromId, to: toId, contract: contract),
          widget.library,
        );
    _clearWire();
  }

  void _zoomBy(double factor) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final current = _transform.value.getMaxScaleOnAxis();
    final nextScale = (current * factor).clamp(composeMinScale, composeMaxScale);
    final applied = nextScale / current;
    final center = Offset(box.size.width / 2, box.size.height / 2);
    final scene = _transform.toScene(center);
    final next = _transform.value.clone()
      ..translateByDouble(scene.dx, scene.dy, 0, 1)
      ..scaleByDouble(applied, applied, 1, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
    _transform.value = next;
  }

  void _scheduleFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitView(retry: 6);
    });
  }

  void _fitView({int retry = 0}) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) {
      if (retry > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitView(retry: retry - 1);
        });
      }
      return;
    }
    final graph = ref.read(composeEditorProvider).graph;
    final bounds = composeNodesBounds(graph.nodes, widget.library);
    _transform.value = composeFitMatrix(
      content: bounds,
      viewport: box.size,
    );
  }

  void _onBackgroundPointerDown(PointerDownEvent event) {
    if (_wiring || _dragging) return;
    final scene = _toScene(event.position);
    _backgroundDown = scene;
    _canvasPanPointer = event.pointer;
    _canvasPanLastGlobal = event.position;
    _canvasPanning = false;
    if (HardwareKeyboard.instance.isShiftPressed) {
      setState(() {
        _marqueePointer = event.pointer;
        _marqueeStart = scene;
        _marqueeEnd = scene;
      });
    }
  }

  void _onBackgroundPointerMove(PointerMoveEvent event) {
    if (_marqueePointer == event.pointer && _marqueeStart != null) {
      setState(() => _marqueeEnd = _toScene(event.position));
      return;
    }
    if (_canvasPanPointer != event.pointer || _canvasPanLastGlobal == null) {
      return;
    }
    if (_wiring || _dragging) return;
    if (!_canvasPanning) {
      if ((event.position - _canvasPanLastGlobal!).distance <=
          composePointerSlop) {
        return;
      }
      _canvasPanning = true;
    }
    _panViewer(_canvasPanLastGlobal!, event.position);
    _canvasPanLastGlobal = event.position;
  }

  void _onBackgroundPointerUp(PointerEvent event) {
    if (_marqueePointer == event.pointer) {
      final start = _marqueeStart;
      final end = _marqueeEnd ?? start;
      setState(() {
        _marqueeStart = null;
        _marqueeEnd = null;
        _marqueePointer = null;
      });
      _backgroundDown = null;
      _canvasPanPointer = null;
      _canvasPanLastGlobal = null;
      _canvasPanning = false;
      if (start == null || end == null) return;
      final rect = Rect.fromPoints(start, end);
      if (rect.shortestSide < 4) {
        if (!_additiveKeys) {
          ref.read(composeEditorProvider.notifier).selectNode(null);
        }
        return;
      }
      final ids = composeNodesInRect(
        ref.read(composeEditorProvider).graph,
        widget.library,
        rect,
      );
      ref.read(composeEditorProvider.notifier).selectNodes(
            ids,
            additive: _additiveKeys,
          );
      return;
    }

    final down = _backgroundDown;
    final panned = _canvasPanning;
    _backgroundDown = null;
    _canvasPanPointer = null;
    _canvasPanLastGlobal = null;
    _canvasPanning = false;
    if (panned || down == null || _wiring || _dragging) return;
    if (!_additiveKeys) {
      ref.read(composeEditorProvider.notifier).selectNode(null);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final l10n = AppLocalizations.of(context);
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_wiring) {
        _clearWire();
        return KeyEventResult.handled;
      }
      if (_marquee) {
        setState(() {
          _marqueeStart = null;
          _marqueeEnd = null;
          _marqueePointer = null;
        });
        return KeyEventResult.handled;
      }
      ref.read(composeEditorProvider.notifier).selectNode(null);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      ref.read(composeEditorProvider.notifier).removeSelected();
      return KeyEventResult.handled;
    }
    if ((HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) &&
        key == LogicalKeyboardKey.keyA) {
      ref.read(composeEditorProvider.notifier).selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(1.15);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(1 / 1.15);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 && l10n != null) {
      _fitView();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(composeEditorProvider);
    ref.listen(
      composeEditorProvider.select((s) => (s.graph.intentName, s.viewEpoch)),
      (previous, next) {
        if (previous == next) return;
        _scheduleFit();
      },
    );
    final graph = _displayGraph(editor.graph);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final l10n = AppLocalizations.of(context)!;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_wiring) {
            _clearWire();
          } else {
            ref.read(composeEditorProvider.notifier).selectNode(null);
          }
        },
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: SizedBox.expand(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: onSurface.withValues(alpha: 0.04),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sceneSize = composeSceneSize(constraints.biggest);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _syncDropOrigin();
                  });
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      InteractiveViewer(
                        key: _viewerKey,
                        transformationController: _transform,
                        constrained: false,
                        alignment: Alignment.topLeft,
                        clipBehavior: Clip.hardEdge,
                        minScale: composeMinScale,
                        maxScale: composeMaxScale,
                        panEnabled: false,
                        scaleEnabled: !_wiring && !_marquee,
                        boundaryMargin: const EdgeInsets.all(1200),
                        child: SizedBox(
                          width: sceneSize.width,
                          height: sceneSize.height,
                          child: Listener(
                            onPointerSignal: _onTrackpadScroll,
                            child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Listener(
                                  behavior: HitTestBehavior.translucent,
                                  onPointerDown: _onBackgroundPointerDown,
                                  onPointerMove: _onBackgroundPointerMove,
                                  onPointerUp: _onBackgroundPointerUp,
                                  onPointerCancel: _onBackgroundPointerUp,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _EdgesPainter(
                                      graph: graph,
                                      library: widget.library,
                                      wireFrom: _wireFromId == null
                                          ? null
                                          : pinPosition(
                                              graph.nodeById(_wireFromId!)!,
                                              widget.library,
                                              _wireContract!,
                                              output: true,
                                            ),
                                      wireTo: _wireEnd,
                                      wireColor: _wireContract == null
                                          ? Brand.primary
                                          : composeContractColor(
                                              _wireContract!),
                                      marquee: _marqueeStart == null ||
                                              _marqueeEnd == null
                                          ? null
                                          : Rect.fromPoints(
                                              _marqueeStart!,
                                              _marqueeEnd!,
                                            ),
                                      marqueeColor: Brand.info,
                                    ),
                                  ),
                                ),
                              ),
                              for (final node in graph.nodes)
                                Positioned(
                                  key: ValueKey(node.id),
                                  left: node.x,
                                  top: node.y,
                                  child: _ComposeNodeCard(
                                    node: node,
                                    library: widget.library,
                                    selected: editor.selectedNodeIds
                                        .contains(node.id),
                                    highlightContract: _wireContract,
                                    onSelect: () => ref
                                        .read(composeEditorProvider.notifier)
                                        .selectNode(
                                          node.id,
                                          additive: _additiveKeys,
                                        ),
                                    onDragStart: (origin) =>
                                        _onCardPointerDown(node, origin),
                                    onDragUpdate: (global) =>
                                        _onCardPointerMove(node, global),
                                    onDragEnd: () => _onCardPointerUp(node),
                                    onOutputDown: (contract, global, pointer) =>
                                        _onOutputPinDown(
                                      node.id,
                                      contract,
                                      global,
                                      pointer,
                                    ),
                                    onOutputMove: (global, pointer) =>
                                        _onOutputPinMove(global, pointer),
                                    onOutputUp: (global, pointer) =>
                                        _onOutputPinUp(global, pointer),
                                    onInputDown: (contract, global, pointer) =>
                                        _onInputPinDown(
                                      node.id,
                                      contract,
                                      global,
                                      pointer,
                                    ),
                                    onInputUp: (contract, pointer) =>
                                        _onInputPinUp(
                                      node.id,
                                      contract,
                                      pointer,
                                    ),
                                  ),
                                ),
                            ],
                            ),
                          ),
                        ),
                      ),
                      if (_clickWiring)
                        Positioned.fill(
                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerHover: (event) =>
                                _updateWire(event.position),
                            onPointerMove: (event) =>
                                _updateWire(event.position),
                            onPointerDown: _onWirePointerDown,
                            onPointerUp: (event) =>
                                _tryCompleteWire(event.position),
                          ),
                        ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: _CanvasTools(
                          onZoomIn: () => _zoomBy(1.15),
                          onZoomOut: () => _zoomBy(1 / 1.15),
                          onFit: _fitView,
                          zoomInTooltip: l10n.composeZoomIn,
                          zoomOutTooltip: l10n.composeZoomOut,
                          fitTooltip: l10n.composeFitView,
                        ),
                      ),
                      if (graph.nodes.isEmpty)
                        IgnorePointer(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                l10n.composeEmptyCanvas,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: Brand.fontFamily,
                                  color: onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _hitInputPin(ComposeGraph graph, Offset scene, String contract) {
    for (final node in graph.nodes) {
      final spec = specForNode(node, widget.library);
      if (!spec.requires.containsKey(contract)) continue;
      final pos = pinPosition(node, widget.library, contract, output: false);
      if ((pos - scene).distance <= 28) return node.id;
    }
    return null;
  }

  String? _hitOutputPin(ComposeGraph graph, Offset scene) {
    for (final node in graph.nodes) {
      final spec = specForNode(node, widget.library);
      for (final contract in spec.provides.keys) {
        final pos = pinPosition(node, widget.library, contract, output: true);
        if ((pos - scene).distance <= 28) return node.id;
      }
    }
    return null;
  }
}

Size composeSceneSize(Size viewport) {
  final width = viewport.width.isFinite
      ? math.max(composeCanvasWidth, viewport.width / composeMinScale)
      : composeCanvasWidth;
  final height = viewport.height.isFinite
      ? math.max(composeCanvasHeight, viewport.height / composeMinScale)
      : composeCanvasHeight;
  return Size(width, height);
}

double composePinStride() => composePinRowHeight + composePinHitSlop;

double composeNodeHeight(ComposeNode node, MarketplaceLibrary library) {
  final spec = specForNode(node, library);
  final rows = math.max(
    composeInputContracts(spec).length,
    composeOutputRowCount(spec),
  );
  return composeNodeHeaderHeight +
      composeNodePinsPaddingTop +
      math.max(rows, 1) * composePinStride() +
      composeNodePinsPaddingBottom +
      composeNodeFooterHeight;
}

Rect composeNodeRect(ComposeNode node, MarketplaceLibrary library) {
  return Rect.fromLTWH(
    node.x,
    node.y,
    composeNodeWidth,
    composeNodeHeight(node, library),
  );
}

Rect composeNodesBounds(
  Iterable<ComposeNode> nodes,
  MarketplaceLibrary library,
) {
  Rect? bounds;
  for (final node in nodes) {
    final rect = composeNodeRect(node, library);
    bounds = bounds == null ? rect : bounds.expandToInclude(rect);
  }
  return bounds ?? Rect.zero;
}

Set<String> composeNodesInRect(
  ComposeGraph graph,
  MarketplaceLibrary library,
  Rect rect,
) {
  return {
    for (final node in graph.nodes)
      if (composeNodeRect(node, library).overlaps(rect)) node.id,
  };
}

Matrix4 composeFitMatrix({
  required Rect content,
  required Size viewport,
  double minScale = composeMinScale,
  double maxScale = composeMaxScale,
  double padding = 48,
}) {
  if (content.isEmpty || !viewport.isFinite || viewport.isEmpty) {
    return Matrix4.identity();
  }
  final padded = content.inflate(padding);
  final scale = (math.min(
    viewport.width / padded.width,
    viewport.height / padded.height,
  ))
      .clamp(minScale, maxScale);
  final dx = (viewport.width - padded.width * scale) / 2 - padded.left * scale;
  final dy =
      (viewport.height - padded.height * scale) / 2 - padded.top * scale;
  return Matrix4.identity()
    ..translateByDouble(dx, dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);
}

Offset pinPosition(
  ComposeNode node,
  MarketplaceLibrary library,
  String contract, {
  required bool output,
}) {
  final spec = specForNode(node, library);
  final keys =
      output ? composeOutputContracts(spec) : composeInputContracts(spec);
  final index = math.max(keys.indexOf(contract), 0);
  final stride = composePinStride();
  final y = node.y +
      composeNodeHeaderHeight +
      composeNodePinsPaddingTop +
      index * stride +
      stride / 2;
  const pinCenterInset = 2.0 + composePinHitSlop / 2 + composePinBulletSize / 2;
  final x = output
      ? node.x + composeNodeWidth - pinCenterInset
      : node.x + pinCenterInset;
  return Offset(x, y);
}

class _CanvasTools extends StatelessWidget {
  const _CanvasTools({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.zoomInTooltip,
    required this.zoomOutTooltip,
    required this.fitTooltip,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final String zoomInTooltip;
  final String zoomOutTooltip;
  final String fitTooltip;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolButton(
            key: const ValueKey('compose-zoom-out'),
            icon: Icons.remove,
            tooltip: zoomOutTooltip,
            onPressed: onZoomOut,
            onSurface: onSurface,
          ),
          _toolButton(
            key: const ValueKey('compose-zoom-in'),
            icon: Icons.add,
            tooltip: zoomInTooltip,
            onPressed: onZoomIn,
            onSurface: onSurface,
          ),
          _toolButton(
            key: const ValueKey('compose-fit'),
            icon: Icons.fit_screen,
            tooltip: fitTooltip,
            onPressed: onFit,
            onSurface: onSurface,
          ),
        ],
      ),
    );
  }

  Widget _toolButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color onSurface,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: onSurface.withValues(alpha: 0.8)),
    );
  }
}

class _ComposeNodeCard extends StatelessWidget {
  const _ComposeNodeCard({
    required this.node,
    required this.library,
    required this.selected,
    required this.onSelect,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onOutputDown,
    required this.onOutputMove,
    required this.onOutputUp,
    required this.onInputDown,
    required this.onInputUp,
    this.highlightContract,
  });

  final ComposeNode node;
  final MarketplaceLibrary library;
  final bool selected;
  final String? highlightContract;
  final VoidCallback onSelect;
  final void Function(Offset globalOrigin) onDragStart;
  final void Function(Offset global) onDragUpdate;
  final VoidCallback onDragEnd;
  final void Function(String contract, Offset global, int pointer) onOutputDown;
  final void Function(Offset global, int pointer) onOutputMove;
  final void Function(Offset global, int pointer) onOutputUp;
  final void Function(String contract, Offset global, int pointer) onInputDown;
  final void Function(String contract, int pointer) onInputUp;

  @override
  Widget build(BuildContext context) {
    final spec = specForNode(node, library);
    final branding = _nodeAccent(node, library);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final requires = composeInputContracts(spec);
    final provides = composeOutputContracts(spec);
    final httpOutputs = composeHttpOutputs(spec);
    final hasPins = requires.isNotEmpty ||
        provides.isNotEmpty ||
        httpOutputs.isNotEmpty;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        onSelect();
        onDragStart(event.position);
      },
      onPointerMove: (event) => onDragUpdate(event.position),
      onPointerUp: (_) => onDragEnd(),
      onPointerCancel: (_) => onDragEnd(),
      child: Container(
        key: ValueKey('compose-node-${node.id}'),
        width: composeNodeWidth,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? branding : onSurface.withValues(alpha: 0.18),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: composeNodeHeaderHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: branding.withValues(alpha: 0.16),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(9)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      _NodeBadge(node: node, library: library),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          node.role,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: Brand.fontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                2,
                composeNodePinsPaddingTop,
                2,
                composeNodePinsPaddingBottom,
              ),
              child: !hasPins
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          node.displayLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: Brand.fontFamily,
                            color: onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final contract in requires)
                                _PinRow(
                                  pinKey: ValueKey(
                                    'compose-pin-in-${node.id}-$contract',
                                  ),
                                  label: composePinLabel(contract),
                                  color: composeContractColor(contract),
                                  alignEnd: false,
                                  lit: highlightContract == contract,
                                  multiple:
                                      composeInputFansIn(spec, contract),
                                  mandatory: composeContractRequired(
                                    spec,
                                    contract,
                                  ),
                                  onPointerDown: (event) => onInputDown(
                                    contract,
                                    event.position,
                                    event.pointer,
                                  ),
                                  onPointerMove: null,
                                  onPointerUp: (event) => onInputUp(
                                    contract,
                                    event.pointer,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final contract in provides)
                                _PinRow(
                                  pinKey: ValueKey(
                                    'compose-pin-out-${node.id}-$contract',
                                  ),
                                  label: composePinLabel(contract),
                                  color: composeContractColor(contract),
                                  alignEnd: true,
                                  lit: highlightContract == contract,
                                  multiple: composeOutputFansOut(contract),
                                  onPointerDown: (event) => onOutputDown(
                                    contract,
                                    event.position,
                                    event.pointer,
                                  ),
                                  onPointerMove: (event) => onOutputMove(
                                    event.position,
                                    event.pointer,
                                  ),
                                  onPointerUp: (event) => onOutputUp(
                                    event.position,
                                    event.pointer,
                                  ),
                                ),
                              for (final output in httpOutputs)
                                _PinRow(
                                  pinKey: ValueKey(
                                    'compose-http-${node.id}-${output.pointer}',
                                  ),
                                  label: composeHttpOutputLabel(output),
                                  color: composeHttpOutputColor,
                                  alignEnd: true,
                                  lit: false,
                                  multiple: false,
                                  http: true,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: onSurface.withValues(alpha: 0.10)),
                ),
              ),
              child: SizedBox(
                key: ValueKey('compose-node-footer-${node.id}'),
                height: composeNodeFooterHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      composeResourceFooter(
                        node,
                        node.isService
                            ? library.lookup(node.serviceId)
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: Brand.fontFamily,
                        color: onSurface.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _nodeAccent(ComposeNode node, MarketplaceLibrary library) {
  switch (node.kind) {
    case ComposeNodeKind.vm:
      return distroBranding(node.label.isEmpty ? node.image : node.label)
          .accent;
    case ComposeNodeKind.llm:
      return modelProviderBranding(
        provider: '',
        id: node.modelId,
        name: node.label,
      ).accent;
    case ComposeNodeKind.service:
      final service = library.lookup(node.serviceId);
      return serviceBranding(node.serviceId, service: service).accent;
  }
}

class _NodeBadge extends StatelessWidget {
  const _NodeBadge({required this.node, required this.library});

  final ComposeNode node;
  final MarketplaceLibrary library;

  @override
  Widget build(BuildContext context) {
    switch (node.kind) {
      case ComposeNodeKind.vm:
        return DistroLogoBadge(
          branding: distroBranding(node.label),
          size: 22,
        );
      case ComposeNodeKind.llm:
        return ModelProviderBadge(
          branding: modelProviderBranding(
            provider: '',
            id: node.modelId,
            name: node.label,
          ),
          size: 22,
        );
      case ComposeNodeKind.service:
        final service = library.lookup(node.serviceId);
        return ServiceIconBadge(
          branding: serviceBranding(node.serviceId, service: service),
          size: 22,
        );
    }
  }
}

class _PinRow extends StatelessWidget {
  const _PinRow({
    required this.label,
    required this.color,
    required this.alignEnd,
    required this.lit,
    required this.multiple,
    this.pinKey,
    this.http = false,
    this.mandatory = false,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
  });

  final Key? pinKey;
  final String label;
  final Color color;
  final bool alignEnd;
  final bool lit;
  final bool multiple;
  final bool http;
  final bool mandatory;
  final void Function(PointerDownEvent event)? onPointerDown;
  final void Function(PointerMoveEvent event)? onPointerMove;
  final void Function(PointerEvent event)? onPointerUp;

  @override
  Widget build(BuildContext context) {
    Widget pin = Padding(
      padding: const EdgeInsets.all(composePinHitSlop / 2),
      child: ComposePinBullet(
        color: color,
        multiple: multiple,
        lit: lit,
        http: http,
      ),
    );
    if (onPointerDown != null) {
      pin = Listener(
        key: pinKey,
        behavior: HitTestBehavior.opaque,
        onPointerDown: onPointerDown,
        onPointerMove: onPointerMove,
        onPointerUp: onPointerUp,
        onPointerCancel: onPointerUp,
        child: pin,
      );
    } else {
      pin = IgnorePointer(key: pinKey, child: pin);
    }

    final style = TextStyle(
      fontSize: 11,
      fontFamily: Brand.fontFamily,
      color: color,
      fontWeight: FontWeight.w600,
    );
    final text = Text.rich(
      TextSpan(
        text: label,
        children: [
          if (mandatory)
            TextSpan(
              text: ' $composeRequiredMark',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: style,
    );

    return SizedBox(
      height: composePinRowHeight + composePinHitSlop,
      child: Row(
        children: alignEnd
            ? [Expanded(child: text), pin]
            : [pin, Expanded(child: text)],
      ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.graph,
    required this.library,
    required this.wireColor,
    required this.marqueeColor,
    this.wireFrom,
    this.wireTo,
    this.marquee,
  });

  final ComposeGraph graph;
  final MarketplaceLibrary library;
  final Color wireColor;
  final Color marqueeColor;
  final Offset? wireFrom;
  final Offset? wireTo;
  final Rect? marquee;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in graph.edges) {
      final from = graph.nodeById(edge.from);
      final to = graph.nodeById(edge.to);
      if (from == null || to == null) continue;
      final start = pinPosition(from, library, edge.contract, output: true);
      final end = pinPosition(to, library, edge.contract, output: false);
      final paint = Paint()
        ..color = composeContractColor(edge.contract)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      _curve(canvas, paint, start, end);
    }

    if (wireFrom != null && wireTo != null) {
      final live = Paint()
        ..color = wireColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      _curve(canvas, live, wireFrom!, wireTo!);
    }

    if (marquee != null && marquee!.shortestSide > 2) {
      final fill = Paint()
        ..color = marqueeColor.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      final stroke = Paint()
        ..color = marqueeColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawRect(marquee!, fill);
      canvas.drawRect(marquee!, stroke);
    }
  }

  void _curve(Canvas canvas, Paint paint, Offset start, Offset end) {
    final path = Path()..moveTo(start.dx, start.dy);
    final mid = (end.dx - start.dx).abs().clamp(40.0, 160.0);
    path.cubicTo(
      start.dx + mid,
      start.dy,
      end.dx - mid,
      end.dy,
      end.dx,
      end.dy,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) {
    return oldDelegate.graph != graph ||
        oldDelegate.library != library ||
        oldDelegate.wireFrom != wireFrom ||
        oldDelegate.wireTo != wireTo ||
        oldDelegate.wireColor != wireColor ||
        oldDelegate.marquee != marquee ||
        oldDelegate.marqueeColor != marqueeColor;
  }
}
