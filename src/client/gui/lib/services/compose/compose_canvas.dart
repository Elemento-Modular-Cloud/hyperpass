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

const composeNodeWidth = 228.0;
const composeNodeHeaderHeight = 42.0;
const composePinRowHeight = 22.0;
const composeNodePinsPaddingTop = 4.0;
const composeNodePinsPaddingBottom = 6.0;
const composePinHitSlop = 10.0;

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
  Offset? _dragNodeStart;
  Offset? _dragPointerStart;
  String? _wireFromId;
  String? _wireContract;
  Offset? _wireEnd;
  int? _wirePointer;

  bool get _wiring => _wireFromId != null;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Offset _toScene(Offset global) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return _transform.toScene(global);
    }
    return _transform.toScene(box.globalToLocal(global));
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

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(composeEditorProvider);
    final graph = editor.graph;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _clearWire,
      },
      child: Focus(
        autofocus: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: onSurface.withValues(alpha: 0.04),
            child: Stack(
              children: [
                GestureDetector(
                  onPanUpdate: (details) {
                    if (_wiring || _dragNodeId != null) return;
                    final next = _transform.value.clone()
                      ..translateByDouble(
                        details.delta.dx,
                        details.delta.dy,
                        0,
                        1,
                      );
                    _transform.value = next;
                  },
                  child: InteractiveViewer(
                    key: _viewerKey,
                    transformationController: _transform,
                    constrained: false,
                    minScale: 0.4,
                    maxScale: 2.2,
                    panEnabled: false,
                    scaleEnabled: !_wiring,
                    boundaryMargin: const EdgeInsets.all(800),
                    child: SizedBox(
                      width: 2400,
                      height: 1600,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _EdgesPainter(
                                graph: graph,
                                library: widget.library,
                                color: onSurface.withValues(alpha: 0.45),
                                accent: Brand.primary,
                                wireFrom: _wireFromId == null
                                    ? null
                                    : pinPosition(
                                        graph.nodeById(_wireFromId!)!,
                                        widget.library,
                                        _wireContract!,
                                        output: true,
                                      ),
                                wireTo: _wireEnd,
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
                                selected: editor.selectedNodeId == node.id,
                                highlightContract: _wireContract,
                                wiring: _wiring,
                                onSelect: () => ref
                                    .read(composeEditorProvider.notifier)
                                    .selectNode(node.id),
                                onDragStart: (origin) {
                                  _dragNodeId = node.id;
                                  _dragNodeStart = Offset(node.x, node.y);
                                  _dragPointerStart = origin;
                                },
                                onDragUpdate: (global) {
                                  if (_dragNodeId != node.id ||
                                      _dragNodeStart == null ||
                                      _dragPointerStart == null) {
                                    return;
                                  }
                                  final delta = _toScene(global) -
                                      _toScene(_dragPointerStart!);
                                  ref
                                      .read(composeEditorProvider.notifier)
                                      .moveNode(
                                        node.id,
                                        _dragNodeStart!.dx + delta.dx,
                                        _dragNodeStart!.dy + delta.dy,
                                      );
                                },
                                onDragEnd: () {
                                  if (_dragNodeId == node.id) {
                                    _dragNodeId = null;
                                    _dragNodeStart = null;
                                    _dragPointerStart = null;
                                  }
                                },
                                onOutputDown: (contract, global, pointer) =>
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
                ),
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerHover: (event) {
                      if (_wiring) _updateWire(event.position);
                    },
                    onPointerMove: (event) {
                      if (_wiring) _updateWire(event.position);
                    },
                    onPointerDown: _onWirePointerDown,
                    onPointerUp: (event) {
                      if (_wiring) _tryCompleteWire(event.position);
                    },
                  ),
                ),
                if (graph.nodes.isEmpty)
                  IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          AppLocalizations.of(context)!.composeEmptyCanvas,
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
  const pinCenterInset = 2.0 + composePinHitSlop / 2 + 6.0;
  final x = output
      ? node.x + composeNodeWidth - pinCenterInset
      : node.x + pinCenterInset;
  return Offset(x, y);
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
                                  alignEnd: false,
                                  lit: highlightContract == contract,
                                  fanOut: composeInputFansIn(spec, contract),
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
                                  alignEnd: true,
                                  lit: highlightContract == contract,
                                  fanOut: composeOutputFansOut(contract),
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
    required this.alignEnd,
    required this.lit,
    required this.fanOut,
    required this.onPointerDown,
  });

  final String label;
  final bool alignEnd;
  final bool lit;
  final bool fanOut;
  final void Function(PointerDownEvent event) onPointerDown;

  @override
  Widget build(BuildContext context) {
    final fill = lit ? Brand.primary : Theme.of(context).colorScheme.onSurface;
    final pin = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: onPointerDown,
      child: Padding(
        padding: const EdgeInsets.all(composePinHitSlop / 2),
        child: SizedBox(
          width: 12,
          height: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(color: Brand.primary, width: 1.5),
            ),
            child: fanOut
                ? Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Brand.primary, width: 1.2),
                        color: lit
                            ? Brand.primary
                            : Theme.of(context).colorScheme.surface,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );

    final text = Text(
      label,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: const TextStyle(fontSize: 11, fontFamily: Brand.fontFamily),
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
    required this.color,
    required this.accent,
    this.wireFrom,
    this.wireTo,
  });

  final ComposeGraph graph;
  final MarketplaceLibrary library;
  final Color color;
  final Color accent;
  final Offset? wireFrom;
  final Offset? wireTo;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    for (final edge in graph.edges) {
      final from = graph.nodeById(edge.from);
      final to = graph.nodeById(edge.to);
      if (from == null || to == null) continue;
      final start = pinPosition(from, library, edge.contract, output: true);
      final end = pinPosition(to, library, edge.contract, output: false);
      _curve(canvas, paint, start, end);
    }

    if (wireFrom != null && wireTo != null) {
      final live = Paint()
        ..color = accent
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      _curve(canvas, live, wireFrom!, wireTo!);
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
