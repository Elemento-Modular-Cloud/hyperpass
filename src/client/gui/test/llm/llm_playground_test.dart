import 'dart:async';
import 'dart:convert';

import 'package:elp_gui/grpc_client.dart';
import 'package:elp_gui/llm/instances/llm_playground.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('builds a localhost chat URL for a loaded llama instance', () {
    final target = LlmPlaygroundTarget.fromLoaded(
      LoadedModelInfo(
        openaiId: 'gemma-2-2b-d21ea046',
        backend: 'llamacpp-metal',
        port: 64852,
        maxTokens: 0,
      ),
    );

    expect(target, isNotNull);
    expect(
      target!.url.toString(),
      'http://127.0.0.1:64852/v1/chat/completions',
    );
    expect(target.model, 'gemma-2-2b-d21ea046');
    expect(target.mlx, isFalse);
  });

  test('uses the vault path as the model id for MLX', () {
    final target = LlmPlaygroundTarget.fromLoaded(
      LoadedModelInfo(
        openaiId: 'gemma-2-2b-9ae40040',
        backend: 'mlx',
        path: '/tmp/mlx-community_Gemma-2-2B-it-4bit',
        port: 52563,
      ),
    );

    expect(target!.model, '/tmp/mlx-community_Gemma-2-2B-it-4bit');
    expect(target.mlx, isTrue);
  });

  test('defers remote models to resolve_model_route', () {
    expect(
      LlmPlaygroundTarget.fromLoaded(
        LoadedModelInfo(
          openaiId: 'openrouter/free',
          backend: 'openai-compat',
          providerId: 'prov-1',
        ),
      ),
      isNull,
    );
  });

  test('maps an openai-compat route onto the provider chat URL', () {
    final target = LlmPlaygroundTarget.fromRoute(
      ResolveModelRouteReply(
        kind: 'openai-compat',
        openaiId: 'openrouter/free',
        baseUrl: 'https://openrouter.ai/api/v1/',
        upstreamModelId: 'openrouter/free',
        apiKey: 'sk-or-v1-secret',
      ),
    );

    expect(
      target.url.toString(),
      'https://openrouter.ai/api/v1/chat/completions',
    );
    expect(target.bearer, 'sk-or-v1-secret');
    expect(target.model, 'openrouter/free');
  });

  test('reads chat content from a non-streaming completion', () {
    expect(
      chatContentFromCompletionJson(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'pong'},
            },
          ],
        }),
      ),
      'pong',
    );
  });

  test('omits max_tokens when session cap is unlimited', () {
    final body = playgroundRequestBody(
      target: LlmPlaygroundTarget(
        url: Uri.parse('http://127.0.0.1:9/v1/chat/completions'),
        model: 'gemma',
      ),
      messages: const [LlmChatTurn(role: 'user', content: 'hi')],
    );
    expect(body.containsKey('max_tokens'), isFalse);
    expect(playgroundMaxTokens(0), isNull);
    expect(playgroundMaxTokens(2048), 2048);
  });

  test('respects an explicit session max_tokens cap', () {
    final body = playgroundRequestBody(
      target: LlmPlaygroundTarget(
        url: Uri.parse('http://127.0.0.1:9/v1/chat/completions'),
        model: 'gemma',
        maxTokens: 1024,
      ),
      messages: const [LlmChatTurn(role: 'user', content: 'hi')],
    );
    expect(body['max_tokens'], 1024);
  });

  test('parses OpenAI SSE deltas', () {
    expect(sseDataPayload('data: {"choices":[{"delta":{"content":"Hi"}}]}'),
        '{"choices":[{"delta":{"content":"Hi"}}]}');
    expect(
      chatDeltaFromSseData('{"choices":[{"delta":{"content":"Hi"}}]}'),
      'Hi',
    );
    expect(chatDeltaFromSseData('[DONE]'), isNull);
  });

  test('reads reasoning_content when content is empty', () {
    expect(
      chatContentFromChoice({
        'delta': {'reasoning_content': 'thinking…'},
      }),
      'thinking…',
    );
    expect(
      chatContentFromCompletionJson(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'reasoning_content': 'only reasoning',
              },
            },
          ],
        }),
      ),
      'only reasoning',
    );
  });

  test('streams a JSON completion through the HTTP client', () async {
    final client = _ScriptedClient((request) {
      expect(request.url.path, '/v1/chat/completions');
      final body = jsonDecode((request as http.Request).body) as Map;
      expect(body['model'], 'gemma');
      expect(body.containsKey('max_tokens'), isFalse);
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'hello from gemma'},
                },
              ],
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final chunks = <String>[];
    await streamPlaygroundChat(
      target: LlmPlaygroundTarget(
        url: Uri.parse('http://127.0.0.1:9/v1/chat/completions'),
        model: 'gemma',
      ),
      messages: const [LlmChatTurn(role: 'user', content: 'hi')],
      httpClient: client,
      onDelta: chunks.add,
    );
    expect(chunks, ['hello from gemma']);
  });
}

class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this._send);

  final http.StreamedResponse Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _send(request);
}
