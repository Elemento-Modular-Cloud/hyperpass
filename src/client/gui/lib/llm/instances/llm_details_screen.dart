import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../brand.dart';
import '../../distro_branding.dart';
import '../../l10n/app_localizations.dart';
import '../../page_surface.dart';
import '../../providers.dart';
import '../llm_id.dart';
import '../providers.dart' as llm;

class LlmDetailsScreen extends ConsumerStatefulWidget {
  final LlmInstanceId id;

  const LlmDetailsScreen(this.id, {super.key});

  @override
  ConsumerState<LlmDetailsScreen> createState() => _LlmDetailsScreenState();
}

class _LlmDetailsScreenState extends ConsumerState<LlmDetailsScreen> {
  late final Terminal _terminal;
  final _scrollController = ScrollController();
  StreamSubscription<StreamModelLogsReply>? _subscription;
  var _streamEnded = false;
  var _hasContent = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 2000);
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = ref.read(grpcClientProvider).streamModelLogs(widget.id.instanceId).listen(
      (reply) {
        if (!reply.hasEntry()) return;
        _appendEntry(reply.entry);
      },
      onError: (_) => setState(() => _streamEnded = true),
      onDone: () => setState(() => _streamEnded = true),
    );
  }

  void _appendEntry(ModelActivityEntry entry) {
    if (!_hasContent) {
      setState(() => _hasContent = true);
    }
    _terminal.write(_formatEntry(entry));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  String _formatEntry(ModelActivityEntry entry) {
    final time = DateTime.fromMillisecondsSinceEpoch(entry.timestampMs.toInt());
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    final color = switch (entry.source) {
      'gateway' => '\x1b[94m',
      'lifecycle' => '\x1b[95m',
      'process' => '\x1b[37m',
      _ => '\x1b[90m',
    };
    return '$color[$stamp] [${entry.source}] ${entry.message}\x1b[0m\r\n';
  }

  Future<void> _unload() async {
    await llm.unloadLlmInstance(ref, widget.id.instanceId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final branding = distroBranding('');
    final loaded = ref.watch(llm.loadedModelsProvider);
    final pending = ref.watch(llm.pendingLlmUnloadsProvider);
    final modelInfo = loaded.whenOrNull(
      data: (reply) {
        for (final model in reply.models) {
          if (model.instanceId == widget.id.instanceId &&
              !pending.contains(model.instanceId)) {
            return model;
          }
        }
        return null;
      },
    );

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.id.displayLabel,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (modelInfo != null) ...[
                  Text(
                    '${modelInfo.backend} · ${modelInfo.state} · 127.0.0.1:${modelInfo.port}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  TextButton(onPressed: _unload, child: Text(l10n.modelsUnload)),
                ] else if (_streamEnded)
                  Text(l10n.modelsLoadedEmpty, style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(Brand.radius),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Brand.radius),
                  child: _hasContent
                      ? ColoredBox(
                          color: branding.background,
                          child: RawScrollbar(
                            controller: _scrollController,
                            thickness: 9,
                            child: TerminalView(
                              _terminal,
                              readOnly: true,
                              alwaysShowCursor: false,
                              padding: const EdgeInsets.all(4),
                              scrollController: _scrollController,
                              theme: branding.terminalTheme,
                              textStyle: TerminalStyle(
                                fontFamily: 'UbuntuMono',
                                fontFamilyFallback: const ['NotoColorEmoji', 'FreeSans'],
                                fontSize: ref.watch(sessionTerminalFontSizeProvider),
                              ),
                            ),
                          ),
                        )
                      : Center(child: Text(l10n.llmActivityEmpty)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
