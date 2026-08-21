import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  LongPressStartDetails? _lastLongPressStartDetails;

  /// Buffer cell where the current drag selection started. Stable across scrolls.
  CellOffset? _selectionAnchorCell;

  Offset? _lastPointerLocal;
  Timer? _autoScrollTimer;
  double _autoScrollDirection = 0;

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalGestureDetector(
      child: widget.child,
      onTapUp: widget.onTapUp,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onSecondaryTapDown,
      onTertiaryTapUp: onSecondaryTapUp,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDragCancel: onDragCancel,
      onDoubleTapDown: onDoubleTapDown,
    );
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  void onDragStart(DragStartDetails details) {
    _selectionAnchorCell = renderTerminal.getCellOffset(details.localPosition);
    _lastPointerLocal = details.localPosition;

    details.kind == PointerDeviceKind.mouse
        ? renderTerminal.selectCharacters(details.localPosition)
        : renderTerminal.selectWord(details.localPosition);
  }

  void onDragUpdate(DragUpdateDetails details) {
    _lastPointerLocal = details.localPosition;
    _applySelectionToPointer(details.localPosition);
    _updateAutoScroll(details.localPosition);
  }

  void onDragEnd(DragEndDetails details) {
    _finishDragSelection();
  }

  void onDragCancel() {
    _finishDragSelection();
  }

  void _finishDragSelection() {
    _stopAutoScroll();
    _selectionAnchorCell = null;
    _lastPointerLocal = null;
  }

  void _applySelectionToPointer(Offset localPosition) {
    final anchor = _selectionAnchorCell;
    if (anchor == null) return;

    // Map the buffer-stable anchor back to the current viewport so selection
    // survives auto-scroll and shift+wheel scrolling during a drag.
    final startLocal = renderTerminal.getOffset(anchor);
    renderTerminal.selectCharacters(startLocal, localPosition);
  }

  void _updateAutoScroll(Offset localPosition) {
    final height = renderTerminal.size.height;
    final edge = (renderTerminal.lineHeight * 1.5).clamp(24.0, 48.0);
    double direction = 0;
    if (localPosition.dy < edge) {
      direction = -1;
    } else if (localPosition.dy > height - edge) {
      direction = 1;
    }

    if (direction == 0) {
      _stopAutoScroll();
      return;
    }

    _autoScrollDirection = direction;
    _autoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _autoScrollTick(),
    );
  }

  void _autoScrollTick() {
    final scrollController = terminalView.scrollController;
    if (!scrollController.hasClients) return;

    final distance = renderTerminal.lineHeight * _autoScrollDirection;
    final position = scrollController.position;
    final next = (scrollController.offset + distance).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == scrollController.offset) return;

    scrollController.jumpTo(next);

    final pointer = _lastPointerLocal;
    if (pointer != null) {
      _applySelectionToPointer(pointer);
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDirection = 0;
  }
}
