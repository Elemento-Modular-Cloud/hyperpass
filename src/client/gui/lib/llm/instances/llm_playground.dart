import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../grpc_client.dart';
import '../llm_features.dart';
import '../providers.dart';

class LlmChatTurn {
  const LlmChatTurn({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class LlmPlaygroundTarget {
  const LlmPlaygroundTarget({
    required this.url,
    required this.model,
    this.bearer,
    this.mlx = false,
    this.maxTokens = 0,
  });

  final Uri url;
  final String model;
  final String? bearer;
  final bool mlx;
  final int maxTokens;

  static LlmPlaygroundTarget? fromLoaded(LoadedModelInfo model) {
    if (isRemoteLlmModel(model) || model.port <= 0) return null;
    final mlx = isMlxRuntime(model.backend) ||
        model.backend == 'mlx' ||
        model.backend.startsWith('mlx');
    final name = mlx && model.path.isNotEmpty
        ? model.path
        : (model.openaiId.isNotEmpty ? model.openaiId : model.modelId);
    if (name.isEmpty) return null;
    return LlmPlaygroundTarget(
      url: Uri.parse('http://127.0.0.1:${model.port}/v1/chat/completions'),
      model: name,
      mlx: mlx,
      maxTokens: model.maxTokens,
    );
  }

  static LlmPlaygroundTarget fromRoute(ResolveModelRouteReply route) {
    final remote =
        route.kind == 'openai-compat' || route.kind == 'openai_compat';
    if (remote) {
      var base = route.baseUrl.trim();
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      final model = route.upstreamModelId.isNotEmpty
          ? route.upstreamModelId
          : route.openaiId;
      return LlmPlaygroundTarget(
        url: Uri.parse('$base/chat/completions'),
        model: model,
        bearer: route.apiKey.isEmpty ? null : route.apiKey,
        maxTokens: route.maxTokens,
      );
    }
    return LlmPlaygroundTarget(
      url: Uri.parse('http://127.0.0.1:${route.port}/v1/chat/completions'),
      model: route.upstreamModelId.isNotEmpty
          ? route.upstreamModelId
          : route.openaiId,
      maxTokens: route.maxTokens,
    );
  }
}

class LlmPlaygroundException implements Exception {
  const LlmPlaygroundException(this.message);

  final String message;

  @override
  String toString() => message;
}

int playgroundMaxTokens(int sessionMaxTokens, {int cap = 512}) {
  if (sessionMaxTokens > 0 && sessionMaxTokens < cap) return sessionMaxTokens;
  return cap;
}

String? openaiErrorMessage(Object? decoded) {
  if (decoded is! Map) return null;
  final error = decoded['error'];
  if (error is Map) {
    final message = error['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
  }
  final message = decoded['message'];
  if (message is String && message.trim().isNotEmpty) return message.trim();
  return null;
}

String? chatContentFromChoice(Object? choice) {
  if (choice is! Map) return null;
  final message = choice['message'];
  if (message is Map) {
    final content = message['content'];
    if (content is String && content.isNotEmpty) return content;
  }
  final delta = choice['delta'];
  if (delta is Map) {
    final content = delta['content'];
    if (content is String && content.isNotEmpty) return content;
  }
  final text = choice['text'];
  if (text is String && text.isNotEmpty) return text;
  return null;
}

String chatContentFromCompletionJson(String body) {
  final decoded = jsonDecode(body);
  final error = openaiErrorMessage(decoded);
  if (error != null) throw LlmPlaygroundException(error);
  if (decoded is! Map) {
    throw const LlmPlaygroundException('Unexpected reply from the model.');
  }
  final choices = decoded['choices'];
  if (choices is List && choices.isNotEmpty) {
    final content = chatContentFromChoice(choices.first);
    if (content != null) return content;
  }
  throw const LlmPlaygroundException('The model returned an empty reply.');
}

String? sseDataPayload(String line) {
  final trimmed = line.trimRight();
  if (trimmed.isEmpty || trimmed.startsWith(':')) return null;
  if (!trimmed.startsWith('data:')) return null;
  return trimmed.substring(5).trimLeft();
}

/// Yields text deltas from an OpenAI SSE `data:` line. Empty string means skip.
String? chatDeltaFromSseData(String payload) {
  if (payload == '[DONE]') return null;
  final decoded = jsonDecode(payload);
  final error = openaiErrorMessage(decoded);
  if (error != null) throw LlmPlaygroundException(error);
  if (decoded is! Map) return '';
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) return '';
  return chatContentFromChoice(choices.first) ?? '';
}

Map<String, dynamic> playgroundRequestBody({
  required LlmPlaygroundTarget target,
  required List<LlmChatTurn> messages,
  bool stream = true,
}) {
  final body = <String, dynamic>{
    'model': target.model,
    'messages': [for (final turn in messages) turn.toJson()],
    'stream': stream,
    'max_tokens': playgroundMaxTokens(target.maxTokens),
  };
  if (target.mlx) {
    body['seed'] = 1;
    body['stop'] = ['\nUSER:', 'USER:', '<end_of_turn>', '<eos>'];
  }
  return body;
}

Future<void> streamPlaygroundChat({
  required LlmPlaygroundTarget target,
  required List<LlmChatTurn> messages,
  required void Function(String delta) onDelta,
  http.Client? httpClient,
}) async {
  final ownsClient = httpClient == null;
  final client = httpClient ?? http.Client();
  try {
    final request = http.Request('POST', target.url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream, application/json'
      ..body = jsonEncode(
        playgroundRequestBody(
          target: target,
          messages: messages,
        ),
      );
    final bearer = target.bearer;
    if (bearer != null && bearer.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $bearer';
    }

    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw LlmPlaygroundException(_httpError(response.statusCode, body));
    }

    final contentType = response.headers['content-type'] ?? '';
    final looksSse = contentType.contains('text/event-stream');
    var emitted = false;
    var leftover = '';
    final raw = StringBuffer();

    await for (final piece in response.stream.transform(utf8.decoder)) {
      raw.write(piece);
      leftover += piece;
      if (!looksSse &&
          !leftover.contains('\ndata:') &&
          !leftover.startsWith('data:')) {
        continue;
      }
      final lines = leftover.split('\n');
      leftover = lines.removeLast();
      for (final line in lines) {
        final delta = _deltaFromSseLine(line);
        if (delta == null || delta.isEmpty) continue;
        emitted = true;
        onDelta(delta);
      }
    }

    final tail = _deltaFromSseLine(leftover);
    if (tail != null && tail.isNotEmpty) {
      emitted = true;
      onDelta(tail);
    }
    if (emitted) return;

    final body = raw.toString();
    if (body.contains('data:')) {
      throw const LlmPlaygroundException('The model returned an empty reply.');
    }
    final content = chatContentFromCompletionJson(body);
    if (content.isNotEmpty) onDelta(content);
  } finally {
    if (ownsClient) client.close();
  }
}

String _httpError(int status, String body) {
  try {
    final decoded = jsonDecode(body);
    final message = openaiErrorMessage(decoded);
    if (message != null) return message;
  } catch (_) {}
  final trimmed = body.trim();
  if (trimmed.isEmpty) return 'HTTP $status';
  return 'HTTP $status: $trimmed';
}

String? _deltaFromSseLine(String line) {
  final payload = sseDataPayload(line);
  if (payload == null || payload == '[DONE]') return null;
  return chatDeltaFromSseData(payload);
}
