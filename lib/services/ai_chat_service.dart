import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_chat_api_store.dart';
import 'ai_chat_store.dart';

class AiChatService {
  AiChatService({
    this.maxRetries = 2,
    this.minRequestGap = const Duration(milliseconds: 500),
  });

  final int maxRetries;
  final Duration minRequestGap;
  DateTime? _lastRequestAt;

  Future<String> testSettings({required AiChatApiSettings settings}) async {
    return _withRetry(() async {
      await _waitForRateLimit();
      final apiKey = settings.apiKey.trim();
      if (apiKey.isEmpty) {
        throw AiChatException(
          level: AiChatErrorLevel.config,
          message: '请先配置 API Key',
          provider: settings.provider,
        );
      }
      final uri = Uri.parse(
        _joinPath(settings.effectiveBaseUrl(), '/chat/completions'),
      );
      final payload = {
        'model': settings.effectiveModel(),
        'temperature': 0,
        'max_tokens': 8,
        'messages': [
          {'role': 'user', 'content': 'reply ok'},
        ],
      };
      final resp = await _postJson(
        uri,
        provider: settings.provider,
        headers: {'Authorization': 'Bearer $apiKey'},
        payload: payload,
      );
      final choices = resp['choices'];
      if (choices is! List || choices.isEmpty) {
        throw AiChatException(
          level: AiChatErrorLevel.response,
          message: '模型返回为空',
          provider: settings.provider,
        );
      }
      return '配置测试通过：${settings.providerLabel()} 接口可访问';
    }, provider: settings.provider);
  }

  Future<String> chatCompletion({
    required AiChatApiSettings settings,
    required List<AiChatMessage> history,
    required String question,
    String? quote,
  }) async {
    return _withRetry(() async {
      await _waitForRateLimit();
      final apiKey = settings.apiKey.trim();
      if (apiKey.isEmpty) {
        throw AiChatException(
          level: AiChatErrorLevel.config,
          message: '请先配置 API Key',
          provider: settings.provider,
        );
      }
      final messages = <Map<String, dynamic>>[];
      final systemPrompt = settings.systemPrompt.trim();
      if (systemPrompt.isNotEmpty) {
        messages.add({'role': 'system', 'content': systemPrompt});
      }
      for (final item in history) {
        messages.add({
          'role': item.role == AiChatRole.user ? 'user' : 'assistant',
          'content': item.role == AiChatRole.user
              ? _buildPrompt(question: item.content, quote: item.quote)
              : item.content,
        });
      }
      final prompt = _buildPrompt(question: question, quote: quote);
      messages.add({'role': 'user', 'content': prompt});
      final uri = Uri.parse(
        _joinPath(settings.effectiveBaseUrl(), '/chat/completions'),
      );
      final payload = {
        'model': settings.effectiveModel(),
        'temperature': settings.temperature.clamp(0, 1.5),
        'messages': messages,
      };
      final resp = await _postJson(
        uri,
        provider: settings.provider,
        headers: {'Authorization': 'Bearer $apiKey'},
        payload: payload,
      );
      final choices = resp['choices'];
      if (choices is! List || choices.isEmpty) {
        throw AiChatException(
          level: AiChatErrorLevel.response,
          message: '模型返回为空',
          provider: settings.provider,
        );
      }
      final first = choices.first;
      if (first is! Map<String, dynamic>) {
        throw AiChatException(
          level: AiChatErrorLevel.response,
          message: '模型返回格式不正确',
          provider: settings.provider,
        );
      }
      final message = first['message'];
      if (message is! Map<String, dynamic>) {
        throw AiChatException(
          level: AiChatErrorLevel.response,
          message: '模型返回格式不正确',
          provider: settings.provider,
        );
      }
      return _extractMessageText(
        message['content'],
        provider: settings.provider,
      );
    }, provider: settings.provider);
  }

  Future<String> simpleCompletion({
    required AiChatApiSettings settings,
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.2,
  }) async {
    return _withRetry(() async {
      await _waitForRateLimit();
      final apiKey = settings.apiKey.trim();
      if (apiKey.isEmpty) {
        throw AiChatException(
          level: AiChatErrorLevel.config,
          message: '请先配置 API Key',
          provider: settings.provider,
        );
      }
      final uri = Uri.parse(
        _joinPath(settings.effectiveBaseUrl(), '/chat/completions'),
      );
      final payload = {
        'model': settings.effectiveModel(),
        'temperature': temperature.clamp(0, 1.5),
        'messages': [
          if (systemPrompt.trim().isNotEmpty)
            {'role': 'system', 'content': systemPrompt.trim()},
          {'role': 'user', 'content': userPrompt},
        ],
      };
      final resp = await _postJson(
        uri,
        provider: settings.provider,
        headers: {'Authorization': 'Bearer $apiKey'},
        payload: payload,
      );
      final choices = resp['choices'];
      if (choices is! List || choices.isEmpty) {
        throw AiChatException(
          level: AiChatErrorLevel.response,
          message: '模型返回为空',
          provider: settings.provider,
        );
      }
      final first = choices.first;
      if (first is! Map<String, dynamic>) {
        throw AiChatException(
          level: AiChatErrorLevel.response,
          message: '模型返回格式不正确',
          provider: settings.provider,
        );
      }
      final message = first['message'];
      if (message is! Map<String, dynamic>) {
        throw AiChatException(
          level: AiChatErrorLevel.response,
          message: '模型返回格式不正确',
          provider: settings.provider,
        );
      }
      return _extractMessageText(
        message['content'],
        provider: settings.provider,
      );
    }, provider: settings.provider);
  }

  Stream<String> streamChatCompletion({
    required AiChatApiSettings settings,
    required List<AiChatMessage> history,
    required String question,
    String? quote,
  }) async* {
    await _waitForRateLimit();
    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw AiChatException(
        level: AiChatErrorLevel.config,
        message: '请先配置 API Key',
        provider: settings.provider,
      );
    }
    final messages = <Map<String, dynamic>>[];
    final systemPrompt = settings.systemPrompt.trim();
    if (systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    for (final item in history) {
      messages.add({
        'role': item.role == AiChatRole.user ? 'user' : 'assistant',
        'content': item.role == AiChatRole.user
            ? _buildPrompt(question: item.content, quote: item.quote)
            : item.content,
      });
    }
    final prompt = _buildPrompt(question: question, quote: quote);
    messages.add({'role': 'user', 'content': prompt});
    final uri = Uri.parse(
      _joinPath(settings.effectiveBaseUrl(), '/chat/completions'),
    );
    final payload = {
      'model': settings.effectiveModel(),
      'temperature': settings.temperature.clamp(0, 1.5),
      'stream': true,
      'messages': messages,
    };
    yield* _streamPostJson(
      uri,
      provider: settings.provider,
      headers: {'Authorization': 'Bearer $apiKey'},
      payload: payload,
    );
  }

  Future<void> _waitForRateLimit() async {
    final now = DateTime.now();
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < minRequestGap) {
        await Future<void>.delayed(minRequestGap - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();
  }

  Future<String> _withRetry(
    Future<String> Function() operation, {
    required AiChatApiProvider provider,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await operation();
      } on AiChatException catch (error) {
        attempt += 1;
        if (!error.retryable || attempt > maxRetries) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      } on TimeoutException {
        attempt += 1;
        if (attempt > maxRetries) {
          throw AiChatException(
            level: AiChatErrorLevel.timeout,
            message: '请求超时，请稍后重试',
            provider: provider,
            retryable: true,
          );
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      } on SocketException {
        attempt += 1;
        if (attempt > maxRetries) {
          throw AiChatException(
            level: AiChatErrorLevel.network,
            message: '网络连接失败，请检查网络后重试',
            provider: provider,
            retryable: true,
          );
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri, {
    Map<String, String> headers = const {},
    required Map<String, dynamic> payload,
    required AiChatApiProvider provider,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      for (final header in headers.entries) {
        req.headers.set(header.key, header.value);
      }
      req.add(utf8.encode(jsonEncode(payload)));
      final resp = await req.close().timeout(const Duration(seconds: 45));
      final body = await utf8
          .decodeStream(resp)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw _httpException(
          statusCode: resp.statusCode,
          body: body,
          provider: provider,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw AiChatException(
          level: AiChatErrorLevel.response,
          message: '返回格式不正确',
          provider: provider,
        );
      }
      return decoded;
    } on TimeoutException {
      throw AiChatException(
        level: AiChatErrorLevel.timeout,
        message: '请求超时，请稍后重试',
        provider: provider,
        retryable: true,
      );
    } on SocketException {
      throw AiChatException(
        level: AiChatErrorLevel.network,
        message: '网络连接失败，请检查网络后重试',
        provider: provider,
        retryable: true,
      );
    } finally {
      client.close(force: true);
    }
  }

  Stream<String> _streamPostJson(
    Uri uri, {
    Map<String, String> headers = const {},
    required Map<String, dynamic> payload,
    required AiChatApiProvider provider,
  }) async* {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      for (final header in headers.entries) {
        req.headers.set(header.key, header.value);
      }
      req.add(utf8.encode(jsonEncode(payload)));
      final resp = await req.close().timeout(const Duration(seconds: 60));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final body = await utf8
            .decodeStream(resp)
            .timeout(const Duration(seconds: 20));
        throw _httpException(
          statusCode: resp.statusCode,
          body: body,
          provider: provider,
        );
      }
      final mimeType = resp.headers.contentType?.mimeType ?? '';
      if (mimeType.contains('application/json')) {
        final raw = await utf8
            .decodeStream(resp)
            .timeout(const Duration(seconds: 30));
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw AiChatException(
            level: AiChatErrorLevel.response,
            message: '返回格式不正确',
            provider: provider,
          );
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) {
          throw AiChatException(
            level: AiChatErrorLevel.response,
            message: '模型返回为空',
            provider: provider,
          );
        }
        final first = choices.first;
        if (first is! Map<String, dynamic>) {
          throw AiChatException(
            level: AiChatErrorLevel.response,
            message: '模型返回格式不正确',
            provider: provider,
          );
        }
        final message = first['message'];
        if (message is! Map<String, dynamic>) {
          throw AiChatException(
            level: AiChatErrorLevel.response,
            message: '模型返回格式不正确',
            provider: provider,
          );
        }
        final text = _extractMessageText(
          message['content'],
          provider: provider,
        );
        if (text.isNotEmpty) {
          yield text;
        }
        return;
      }

      await for (final line
          in resp
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(const Duration(seconds: 90))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data == '[DONE]') {
          break;
        }
        dynamic decoded;
        try {
          decoded = jsonDecode(data);
        } catch (_) {
          continue;
        }
        if (decoded is! Map<String, dynamic>) continue;
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final first = choices.first;
        if (first is! Map<String, dynamic>) continue;
        final delta = first['delta'];
        if (delta is! Map<String, dynamic>) continue;
        final content = delta['content'];
        final text = _extractDeltaText(content);
        if (text.isNotEmpty) {
          yield text;
        }
      }
    } on TimeoutException {
      throw AiChatException(
        level: AiChatErrorLevel.timeout,
        message: '请求超时，请稍后重试',
        provider: provider,
        retryable: true,
      );
    } on SocketException {
      throw AiChatException(
        level: AiChatErrorLevel.network,
        message: '网络连接失败，请检查网络后重试',
        provider: provider,
        retryable: true,
      );
    } finally {
      client.close(force: true);
    }
  }

  AiChatException _httpException({
    required int statusCode,
    required String body,
    required AiChatApiProvider provider,
  }) {
    if (statusCode == 401 || statusCode == 403) {
      return AiChatException(
        level: AiChatErrorLevel.auth,
        message: '鉴权失败，请检查密钥和权限',
        provider: provider,
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      return AiChatException(
        level: AiChatErrorLevel.rateLimit,
        message: '请求过于频繁，触发限流，请稍后重试',
        provider: provider,
        statusCode: statusCode,
        retryable: true,
      );
    }
    if (statusCode >= 500) {
      return AiChatException(
        level: AiChatErrorLevel.server,
        message: '服务端异常，请稍后重试',
        provider: provider,
        statusCode: statusCode,
        retryable: true,
      );
    }
    return AiChatException(
      level: AiChatErrorLevel.request,
      message: '请求失败（HTTP $statusCode）',
      provider: provider,
      statusCode: statusCode,
      rawBody: body,
    );
  }

  String _buildPrompt({required String question, String? quote}) {
    final trimmedQuestion = question.trim();
    final trimmedQuote = quote?.trim() ?? '';
    if (trimmedQuote.isEmpty) return trimmedQuestion;
    return '【引用开始】\n$trimmedQuote\n【引用结束】\n\n请基于上述引用内容回答：\n$trimmedQuestion';
  }

  String _extractMessageText(
    dynamic content, {
    required AiChatApiProvider provider,
  }) {
    if (content is String) {
      final text = content.trim();
      if (text.isNotEmpty) return text;
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is Map && item['text'] is String) {
          final text = (item['text'] as String).trim();
          if (text.isNotEmpty) {
            buffer.writeln(text);
          }
        }
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) return text;
    }
    throw AiChatException(
      level: AiChatErrorLevel.response,
      message: '模型没有返回文本内容',
      provider: provider,
    );
  }

  String _extractDeltaText(dynamic content) {
    if (content is String) {
      return content;
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is Map && item['text'] is String) {
          buffer.write(item['text'] as String);
        }
      }
      return buffer.toString();
    }
    return '';
  }

  String _joinPath(String baseUrl, String path) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBase$path';
  }
}

enum AiChatErrorLevel {
  config,
  auth,
  rateLimit,
  timeout,
  network,
  server,
  request,
  response,
}

class AiChatException implements Exception {
  const AiChatException({
    required this.level,
    required this.message,
    required this.provider,
    this.statusCode,
    this.rawBody,
    this.retryable = false,
  });

  final AiChatErrorLevel level;
  final String message;
  final AiChatApiProvider provider;
  final int? statusCode;
  final String? rawBody;
  final bool retryable;

  String userMessage() {
    final prefix = switch (level) {
      AiChatErrorLevel.config => '配置错误',
      AiChatErrorLevel.auth => '鉴权错误',
      AiChatErrorLevel.rateLimit => '限流',
      AiChatErrorLevel.timeout => '超时',
      AiChatErrorLevel.network => '网络错误',
      AiChatErrorLevel.server => '服务异常',
      AiChatErrorLevel.request => '请求错误',
      AiChatErrorLevel.response => '返回格式错误',
    };
    if (statusCode == null) return '$prefix：$message';
    return '$prefix：$message（HTTP $statusCode）';
  }

  @override
  String toString() => userMessage();
}
