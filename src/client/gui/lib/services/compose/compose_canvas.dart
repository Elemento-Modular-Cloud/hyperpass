import 'dart:math' as math;

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
const composePinHitSlop = 10.0;
const composeMinScale = 0.25;
const composeMaxScale = 2.6;
const composeCanvasWidth = 3200.0;
const composeCanvasHeight = 2200.0;

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
  String? _wireFromId;
  String? _wireContract;
  Offset? _wireEnd;
  int? _wirePointer;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  int? _marqueePointer;
  Offset? _backgroundDown;
  bool _shift = false;

  bool get _wiring => _wireFromId != null;
  bool get _dragging => _dragNodeId != null;
  bool get _marquee => _marqueeStart != null;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _transform.dispose();
    super.dispose();
  }

  bool _onHardwareKey(KeyEvent event) {
    _syncModifiers();
    return false;
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

  void _syncModifiers() {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (shift != _shift) setState(() => _shift = shift);
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

  void _tapOutputPin(
      String nodeId, String contract, Offset global, int pointer) {
    if (_wireFromId == nodeId && _wireContract == contract) {
      _clearWire();
      return;
    }
    _beginWire(nodeId, contract, global, pointer);
  }

  void _tapInputPin(String nodeId, String contract) {
    final fromId = _wireFromId;
    final wireContract = _wireContract;
    if (fromId == null || wireContract == null) return;
    if (wireContract != contract) return;
    _commitEdge(fromId, nodeId, contract);
  }

  void _onWirePointerDown(PointerDownEvent event) {
    if (!_wiring) return;
    if (_wirePointer == event.pointer) return;
    _updateWire(event.position);
    final graph = ref.read(composeEditorProvider).graph;
    final contract = _wireContract;
    if (contract == null) return;
    final scene = _toScene(event.position);
    if (_hitInputPin(graph, scene, contract) != null) return;
    if (_hitOutputPin(graph, scene) != null) return;
    _clearWire();
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

  void _fitView() {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
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
    if (HardwareKeyboard.instance.isShiftPressed) {
      setState(() {
        _marqueePointer = event.pointer;
        _marqueeStart = scene;
        _marqueeEnd = scene;
      });
    }
  }

  void _onBackgroundPointerMove(PointerMoveEvent event) {
    if (_marqueePointer != event.pointer || _marqueeStart == null) return;
    setState(() => _marqueeEnd = _toScene(event.position));
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
    _backgroundDown = null;
    if (down == null || _wiring || _dragging) return;
    final moved = (_toScene(event.position) - down).distance;
    if (moved < 4 && !_additiveKeys) {
      ref.read(composeEditorProvider.notifier).selectNode(null);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    _syncModifiers();
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
    final graph = editor.graph;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final l10n = AppLocalizations.of(context)!;
    final panEnabled = !_wiring && !_dragging && !_marquee && !_shift;

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
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      InteractiveViewer(
                        key: _viewerKey,
                        transformationController: _transform,
                        constrained: false,
                        clipBehavior: Clip.hardEdge,
                        minScale: composeMinScale,
                        maxScale: composeMaxScale,
                        panEnabled: panEnabled,
                        scaleEnabled: !_wiring && !_marquee,
                        boundaryMargin: const EdgeInsets.all(1200),
                        child: SizedBox(
                          width: sceneSize.width,
                          height: sceneSize.height,
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
                                  left: node.x,
                                  top: node.y,
                                  child: _ComposeNodeCard(
                                    node: node,
                                    library: widget.library,
                                    selected: editor.selectedNodeIds
                                        .contains(node.id),
                                    highlightContract: _wireContract,
                                    wiring: _wiring,
                                    onSelect: () => ref
                                        .read(composeEditorProvider.notifier)
                                        .selectNode(
                                          node.id,
                                          additive: _additiveKeys,
                                        ),
                                    onDragStart: (origin) {
                                      final notifier = ref.read(
                                        composeEditorProvider.notifier,
                                      );
                                      if (!editor.selectedNodeIds
                                          .contains(node.id)) {
                                        notifier.selectNode(node.id);
                                      }
                                      final selected = {
                                        ...ref
                                            .read(composeEditorProvider)
                                            .selectedNodeIds,
                                        node.id,
                                      };
                                      setState(() {
                                        _dragNodeId = node.id;
                                        _dragPointerStart = origin;
                                        _dragNodeStarts = {
                                          for (final item in graph.nodes)
                                            if (selected.contains(item.id))
                                              item.id:
                                                  Offset(item.x, item.y),
                                        };
                                      });
                                    },
                                    onDragUpdate: (global) {
                                      if (_dragNodeId != node.id ||
                                          _dragPointerStart == null ||
                                          _dragNodeStarts.isEmpty) {
                                        return;
                                      }
                                      final delta = _toScene(global) -
                                          _toScene(_dragPointerStart!);
                                      ref
                                          .read(composeEditorProvider.notifier)
                                          .moveNodes({
                                        for (final entry
                                            in _dragNodeStarts.entries)
                                          entry.key: (
                                            entry.value.dx + delta.dx,
                                            entry.value.dy + delta.dy,
                                          ),
                                      });
                                    },
                                    onDragEnd: () {
                                      if (_dragNodeId == node.id) {
                                        setState(() {
                                          _dragNodeId = null;
                                          _dragNodeStarts = const {};
                                          _dragPointerStart = null;
                                        });
                                      }
                                    },
                                    onOutputDown:
                                        (contract, global, pointer) =>
                                            _tapOutputPin(
                                      node.id,
                                      contract,
                                      global,
                                      pointer,
                                    ),
                                    onInputDown: (contract) =>
                                        _tapInputPin(node.id, contract),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_wiring)
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
                        right: 10,
                        top: 10,
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
    composeOutputContracts(spec).length,
  );
  return composeNodeHeaderHeight +
      composeNodePinsPaddingTop +
      math.max(rows, 1) * composePinStride() +
      composeNodePinsPaddingBottom;
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
    required this.wiring,
    required this.onSelect,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onOutputDown,
    required this.onInputDown,
    this.highlightContract,
  });

  final ComposeNode node;
  final MarketplaceLibrary library;
  final bool selected;
  final bool wiring;
  final String? highlightContract;
  final VoidCallback onSelect;
  final void Function(Offset globalOrigin) onDragStart;
  final void Function(Offset global) onDragUpdate;
  final VoidCallback onDragEnd;
  final void Function(String contract, Offset global, int pointer) onOutputDown;
  final void Function(String contract) onInputDown;

  @override
  Widget build(BuildContext context) {
    final spec = specForNode(node, library);
    final branding = _nodeAccent(node, library);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final requires = composeInputContracts(spec);
    final provides = composeOutputContracts(spec);

    return Container(
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
          GestureDetector(
            onTap: onSelect,
            onPanStart: wiring
                ? null
                : (details) => onDragStart(details.globalPosition),
            onPanUpdate: wiring
                ? null
                : (details) => onDragUpdate(details.globalPosition),
            onPanEnd: wiring ? null : (_) => onDragEnd(),
            child: SizedBox(
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              2,
              composeNodePinsPaddingTop,
              2,
              composeNodePinsPaddingBottom,
            ),
            child: requires.isEmpty && provides.isEmpty
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
                      if (requires.isNotEmpty)
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final contract in requires)
                                _PinRow(
                                  label: composePinLabel(contract),
                                  color: composeContractColor(contract),
                                  alignEnd: false,
                                  lit: highlightContract == contract,
                                  multiple:
                                      composeInputFansIn(spec, contract),
                                  onPointerDown: (_) => onInputDown(contract),
                                ),
                            ],
                          ),
                        ),
                      if (provides.isNotEmpty)
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final contract in provides)
                                _PinRow(
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
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
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
    required this.onPointerDown,
  });

  final String label;
  final Color color;
  final bool alignEnd;
  final bool lit;
  final bool multiple;
  final void Function(PointerDownEvent event) onPointerDown;

  @override
  Widget build(BuildContext context) {
    final pin = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: onPointerDown,
      child: Padding(
        padding: const EdgeInsets.all(composePinHitSlop / 2),
        child: ComposePinBullet(
          color: color,
          multiple: multiple,
          lit: lit,
        ),
      ),
    );

    final text = Text(
      label,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: 11,
        fontFamily: Brand.fontFamily,
        color: color,
        fontWeight: FontWeight.w600,
      ),
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
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) => true;
}
