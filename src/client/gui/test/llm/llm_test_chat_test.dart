import 'dart:async';
import 'dart:convert';

import 'package:elp_gui/grpc_client.dart';
import 'package:elp_gui/l10n/app_localizations.dart';
import 'package:elp_gui/llm/instances/llm_test_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('uses a right rail once the activity pane is wide', () {
    expect(
      showLlmPlaygroundSidebar(const BoxConstraints.tightFor(width: 900)),
      isTrue,
    );
    expect(
      showLlmPlaygroundSidebar(const BoxConstraints.tightFor(width: 899)),
      isFalse,
    );
  });
  testWidgets('sends a prompt to the loaded instance', (tester) async {
    final sent = <String>[];
    final client = _ScriptedClient((request) {
      sent.add((request as http.Request).body);
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'pong'},
                },
              ],
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LlmTestChat(
              instanceId: 'inst-1',
              httpClient: client,
              model: LoadedModelInfo(
                instanceId: 'inst-1',
                openaiId: 'gemma-local',
                backend: 'llamacpp-metal',
                port: 64852,
                state: 'loaded',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Try this model'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('llm-playground-input')), 'ping');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sent, hasLength(1));
    final body = jsonDecode(sent.single) as Map;
    expect(body['model'], 'gemma-local');
    expect(body['messages'], [
      {'role': 'user', 'content': 'ping'},
    ]);
    expect(find.text('ping'), findsOneWidget);
    expect(find.text('pong'), findsOneWidget);
  });

  testWidgets('stays disabled when the instance is not loaded', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LlmTestChat(instanceId: 'gone'),
          ),
        ),
      ),
    );

    expect(find.text('Load the model to try a prompt.'), findsOneWidget);
    final send = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(const Key('llm-playground-send')),
        matching: find.byType(TextButton),
      ),
    );
    expect(send.onPressed, isNull);
  });
}

class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this._send);

  final http.StreamedResponse Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _send(request);
}
