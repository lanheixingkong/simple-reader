import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pdf_text_api_store.dart';

class PdfPageOcrService {
  PdfPageOcrService({
    this.maxRetries = 2,
    this.minRequestGap = const Duration(milliseconds: 700),
  });

  final int maxRetries;
  final Duration minRequestGap;

  DateTime? _lastRequestAt;

  Future<String> testSettings({required PdfTextApiSettings settings}) async {
    return _withRetry(() async {
      await _waitForRateLimit();
      switch (settings.provider) {
        case PdfTextApiProvider.openai:
        case PdfTextApiProvider.aliyun:
          await _probeOpenAiCompatible(settings: settings);
          return '配置测试通过：${settings.providerLabel()} 接口可访问';
        case PdfTextApiProvider.glm:
          await _probeGlmOcr(settings: settings);
          return '配置测试通过：GLM OCR 接口可访问';
      }
    }, provider: settings.provider);
  }

  Future<String> recognizeText({
    required List<int> imageBytes,
    required PdfTextApiSettings settings,
  }) async {
    return _withRetry(() async {
      await _waitForRateLimit();
      switch (settings.provider) {
        case PdfTextApiProvider.openai:
        case PdfTextApiProvider.aliyun:
          return _callOpenAiCompatible(
            imageBytes: imageBytes,
            settings: settings,
          );
        case PdfTextApiProvider.glm:
          return _callGlmOcr(imageBytes: imageBytes, settings: settings);
      }
    }, provider: settings.provider);
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
    required PdfTextApiProvider provider,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await operation();
      } on PdfOcrException catch (error) {
        attempt += 1;
        if (!error.retryable || attempt > maxRetries) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      } on TimeoutException {
        attempt += 1;
        if (attempt > maxRetries) {
          throw PdfOcrException(
            level: PdfOcrErrorLevel.timeout,
            message: '请求超时，请稍后重试',
            provider: provider,
            retryable: true,
          );
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      } on SocketException {
        attempt += 1;
        if (attempt > maxRetries) {
          throw PdfOcrException(
            level: PdfOcrErrorLevel.network,
            message: '网络连接失败，请检查网络后重试',
            provider: provider,
            retryable: true,
          );
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }

  Future<String> _callOpenAiCompatible({
    required List<int> imageBytes,
    required PdfTextApiSettings settings,
  }) async {
    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.config,
        message: '请先配置 API Key',
        provider: settings.provider,
      );
    }
    final baseUrl = settings.effectiveBaseUrl();
    final model = settings.effectiveModel();
    final imageBase64 = base64Encode(imageBytes);
    final uri = Uri.parse(_joinPath(baseUrl, '/chat/completions'));
    const strictSystemPrompt =
        '你是OCR逐字转写引擎。只做忠实转写，不做改写、总结、纠错、翻译或解释。'
        '输出时尽量保持原页面段落、换行和标点。';
    final userPrompt = settings.prompt.trim().isEmpty
        ? '请逐行转写此页面可见文字，保持原排版顺序。'
        : settings.prompt.trim();
    final payload = {
      'model': model,
      'temperature': 0,
      'top_p': 0.1,
      'messages': [
        {'role': 'system', 'content': strictSystemPrompt},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': userPrompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,$imageBase64'},
            },
          ],
        },
      ],
    };
    final resp = await _postJson(
      uri,
      headers: {'Authorization': 'Bearer $apiKey'},
      payload: payload,
      provider: settings.provider,
    );
    final choices = resp['choices'];
    if (choices is! List || choices.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: '模型返回为空',
        provider: settings.provider,
      );
    }
    final message = choices.first['message'];
    if (message is! Map<String, dynamic>) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: '模型返回格式不正确',
        provider: settings.provider,
      );
    }
    return _extractMessageContent(
      message['content'],
      provider: settings.provider,
    );
  }

  Future<void> _probeOpenAiCompatible({
    required PdfTextApiSettings settings,
  }) async {
    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.config,
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
      headers: {'Authorization': 'Bearer $apiKey'},
      payload: payload,
      provider: settings.provider,
    );
    final choices = resp['choices'];
    if (choices is! List || choices.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: '模型返回为空',
        provider: settings.provider,
      );
    }
  }

  Future<void> _probeGlmOcr({required PdfTextApiSettings settings}) async {
    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.config,
        message: '请先配置 API Key',
        provider: settings.provider,
      );
    }
    final uri = Uri.parse(
      _joinPath(settings.effectiveBaseUrl(), '/layout_parsing'),
    );
    final payload = {
      'model': settings.effectiveModel(),
      'file': 'https://cdn.bigmodel.cn/static/logo/introduction.png',
    };
    final resp = await _postJson(
      uri,
      headers: {'Authorization': 'Bearer $apiKey'},
      payload: payload,
      provider: settings.provider,
    );
    if (resp.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: 'GLM OCR 返回为空',
        provider: settings.provider,
      );
    }
  }

  Future<String> _callGlmOcr({
    required List<int> imageBytes,
    required PdfTextApiSettings settings,
  }) async {
    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.config,
        message: '请先配置 API Key',
        provider: settings.provider,
      );
    }
    final uri = Uri.parse(
      _joinPath(settings.effectiveBaseUrl(), '/layout_parsing'),
    );
    final payload = {
      'model': settings.effectiveModel(),
      'file': base64Encode(imageBytes),
    };
    final resp = await _postJson(
      uri,
      headers: {'Authorization': 'Bearer $apiKey'},
      payload: payload,
      provider: settings.provider,
    );
    final text = _extractGlmOcrText(resp).trim();
    if (text.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: 'GLM OCR 未返回可用文本',
        provider: settings.provider,
      );
    }
    return text;
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri, {
    Map<String, String> headers = const {},
    required Map<String, dynamic> payload,
    String contentType = 'application/json',
    required PdfTextApiProvider provider,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.contentTypeHeader, contentType);
      for (final entry in headers.entries) {
        req.headers.set(entry.key, entry.value);
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
        throw PdfOcrException(
          level: PdfOcrErrorLevel.response,
          message: '返回格式不正确',
          provider: provider,
        );
      }
      return decoded;
    } on TimeoutException {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.timeout,
        message: '请求超时，请稍后重试',
        provider: provider,
        retryable: true,
      );
    } on SocketException {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.network,
        message: '网络连接失败，请检查网络后重试',
        provider: provider,
        retryable: true,
      );
    } finally {
      client.close(force: true);
    }
  }

  PdfOcrException _httpException({
    required int statusCode,
    required String body,
    required PdfTextApiProvider provider,
  }) {
    if (statusCode == 401 || statusCode == 403) {
      return PdfOcrException(
        level: PdfOcrErrorLevel.auth,
        message: '鉴权失败，请检查密钥和权限',
        provider: provider,
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      return PdfOcrException(
        level: PdfOcrErrorLevel.rateLimit,
        message: '请求过于频繁，触发限流，请稍后重试',
        provider: provider,
        statusCode: statusCode,
        retryable: true,
      );
    }
    if (statusCode >= 500) {
      return PdfOcrException(
        level: PdfOcrErrorLevel.server,
        message: '服务端异常，请稍后重试',
        provider: provider,
        statusCode: statusCode,
        retryable: true,
      );
    }
    return PdfOcrException(
      level: PdfOcrErrorLevel.request,
      message: '请求失败（HTTP $statusCode）',
      provider: provider,
      statusCode: statusCode,
      rawBody: body,
    );
  }

  String _joinPath(String baseUrl, String path) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBase$path';
  }

  String _extractMessageContent(
    dynamic content, {
    required PdfTextApiProvider provider,
  }) {
    if (content is String) {
      final trimmed = content.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is Map && item['text'] is String) {
          buffer.writeln(item['text'] as String);
        }
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) return text;
    }
    throw PdfOcrException(
      level: PdfOcrErrorLevel.response,
      message: '模型没有返回文本内容',
      provider: provider,
    );
  }

  String _extractGlmOcrText(Map<String, dynamic> resp) {
    final markdown = resp['markdown'] ?? resp['content'];
    if (markdown is String && markdown.trim().isNotEmpty) {
      return markdown;
    }
    final pages = resp['pages'];
    if (pages is List) {
      final buffer = StringBuffer();
      for (final page in pages) {
        if (page is Map && page['markdown'] is String) {
          buffer.writeln((page['markdown'] as String).trim());
        } else if (page is Map && page['text'] is String) {
          buffer.writeln((page['text'] as String).trim());
        }
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) return text;
    }
    final blocks = resp['blocks'];
    if (blocks is List) {
      final buffer = StringBuffer();
      for (final block in blocks) {
        if (block is Map && block['text'] is String) {
          buffer.writeln((block['text'] as String).trim());
        }
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}

enum PdfOcrErrorLevel {
  config,
  auth,
  rateLimit,
  timeout,
  network,
  server,
  request,
  response,
}

class PdfOcrException implements Exception {
  const PdfOcrException({
    required this.level,
    required this.message,
    required this.provider,
    this.statusCode,
    this.providerCode,
    this.rawBody,
    this.retryable = false,
  });

  final PdfOcrErrorLevel level;
  final String message;
  final PdfTextApiProvider provider;
  final int? statusCode;
  final String? providerCode;
  final String? rawBody;
  final bool retryable;

  String userMessage() {
    final prefix = switch (level) {
      PdfOcrErrorLevel.config => '配置错误',
      PdfOcrErrorLevel.auth => '鉴权错误',
      PdfOcrErrorLevel.rateLimit => '限流',
      PdfOcrErrorLevel.timeout => '超时',
      PdfOcrErrorLevel.network => '网络错误',
      PdfOcrErrorLevel.server => '服务异常',
      PdfOcrErrorLevel.request => '请求错误',
      PdfOcrErrorLevel.response => '返回格式错误',
    };
    final codeText = [
      if (statusCode != null) 'HTTP $statusCode',
      if (providerCode != null && providerCode!.isNotEmpty) providerCode,
    ].join(' / ');
    if (codeText.isEmpty) return '$prefix：$message';
    return '$prefix：$message（$codeText）';
  }

  @override
  String toString() => userMessage();
}
