import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../brand.dart';
import '../../grpc_client.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../widgets/launchpad_button.dart';
import 'llm_playground.dart';

/// Wide enough for the activity log plus a dedicated chat rail.
const llmPlaygroundSidebarMinWidth = 900.0;

bool showLlmPlaygroundSidebar(BoxConstraints constraints) =>
    constraints.maxWidth >= llmPlaygroundSidebarMinWidth;

const llmPlaygroundSidebarWidth = 340.0;

class LlmTestChat extends ConsumerStatefulWidget {
  const LlmTestChat({
    required this.instanceId,
    this.model,
    this.httpClient,
    this.resolveRoute,
    this.expanded = false,
    super.key,
  });

  final String instanceId;
  final LoadedModelInfo? model;
  final http.Client? httpClient;
  final Future<ResolveModelRouteReply> Function(String instanceId)?
      resolveRoute;

  /// Fill the parent (right rail) instead of a short bottom strip.
  final bool expanded;

  @override
  ConsumerState<LlmTestChat> createState() => _LlmTestChatState();
}

class _LlmTestChatState extends ConsumerState<LlmTestChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _focus;
  final _turns = <LlmChatTurn>[];
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(onKeyEvent: _onInputKey);
  }

  @override
  void dispose() {
    _focus.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final enter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }

  bool get _ready => widget.model != null && !_busy;

  Future<void> _send() async {
    final prompt = _input.text.trim();
    if (prompt.isEmpty || !_ready) return;
    final model = widget.model!;
    setState(() {
      _error = null;
      _busy = true;
      _turns.add(LlmChatTurn(role: 'user', content: prompt));
      _turns.add(const LlmChatTurn(role: 'assistant', content: ''));
      _input.clear();
    });
    _jumpToEnd();

    try {
      final target = LlmPlaygroundTarget.fromLoaded(model) ??
          LlmPlaygroundTarget.fromRoute(
            await (widget.resolveRoute ??
                ref.read(grpcClientProvider).resolveModelRoute)(
              widget.instanceId,
            ),
          );
      final history = [
        for (final turn in _turns)
          if (turn.role == 'user' || turn.content.isNotEmpty) turn,
      ];
      // The trailing assistant placeholder is not part of the request.
      if (history.isNotEmpty && history.last.role == 'assistant') {
        history.removeLast();
      }
      await streamPlaygroundChat(
        target: target,
        messages: history,
        httpClient: widget.httpClient,
        onDelta: (delta) {
          if (!mounted) return;
          setState(() {
            final last = _turns.last;
            _turns[_turns.length - 1] = LlmChatTurn(
              role: last.role,
              content: last.content + delta,
            );
          });
          _jumpToEnd();
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        if (_turns.isNotEmpty &&
            _turns.last.role == 'assistant' &&
            _turns.last.content.isEmpty) {
          _turns.removeLast();
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    setState(() {
      _turns.clear();
      _error = null;
    });
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final available = widget.model != null;

    final chat = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.llmPlaygroundTitle,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
            if (_turns.isNotEmpty)
              TextButton(
                onPressed: _busy ? null : _clear,
                child: Text(l10n.llmPlaygroundClear),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(Brand.radius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _Transcript(
                turns: _turns,
                busy: _busy,
                available: available,
                error: _error,
                scroll: _scroll,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('llm-playground-input'),
                controller: _input,
                focusNode: _focus,
                enabled: available,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.llmPlaygroundHint,
                ),
              ),
            ),
            const SizedBox(width: 8),
            LaunchPadButton.primary(
              key: const Key('llm-playground-send'),
              compact: true,
              onPressed: _ready ? _send : null,
              child: Text(l10n.llmPlaygroundSend),
            ),
          ],
        ),
      ],
    );

    return KeyedSubtree(
      key: const Key('llm-playground'),
      child: widget.expanded ? chat : SizedBox(height: 220, child: chat),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.turns,
    required this.busy,
    required this.available,
    required this.error,
    required this.scroll,
  });

  final List<LlmChatTurn> turns;
  final bool busy;
  final bool available;
  final String? error;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    if (!available) {
      return Center(
        child: Text(
          l10n.llmPlaygroundUnavailable,
          style:
              TextStyle(color: onSurface.withValues(alpha: 0.6), fontSize: 12),
        ),
      );
    }
    if (turns.isEmpty && error == null) {
      return Center(
        child: Text(
          l10n.llmPlaygroundEmpty,
          style:
              TextStyle(color: onSurface.withValues(alpha: 0.6), fontSize: 12),
        ),
      );
    }

    return ListView(
      controller: scroll,
      children: [
        for (final turn in turns)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: turn.role == 'user'
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: turn.role == 'user'
                        ? Brand.primaryMuted
                        : onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(Brand.radius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      turn.content.isEmpty && busy && turn.role == 'assistant'
                          ? l10n.llmPlaygroundThinking
                          : turn.content,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: onSurface.withValues(
                          alpha: turn.content.isEmpty ? 0.55 : 0.92,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}
