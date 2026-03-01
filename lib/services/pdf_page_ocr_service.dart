import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'pdf_text_api_store.dart';

class PdfPageOcrService {
  PdfPageOcrService({
    this.maxRetries = 2,
    this.minRequestGap = const Duration(milliseconds: 700),
  });

  final int maxRetries;
  final Duration minRequestGap;

  DateTime? _lastRequestAt;
  static final List<int> _probeImageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z4xQAAAAASUVORK5CYII=',
  );

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
    final payload = {
      'model': model,
      'temperature': 0,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': settings.prompt},
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
    final content = message['content'];
    return _extractMessageContent(content, provider: settings.provider);
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
    final baseUrl = settings.effectiveBaseUrl();
    final model = settings.effectiveModel();
    final uri = Uri.parse(_joinPath(baseUrl, '/chat/completions'));
    final payload = {
      'model': model,
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
    final baseUrl = settings.effectiveBaseUrl();
    final model = settings.effectiveModel();
    final uri = Uri.parse(_joinPath(baseUrl, '/layout_parsing'));
    final payload = {
      'model': model,
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
    final baseUrl = settings.effectiveBaseUrl();
    final model = settings.effectiveModel();
    final uri = Uri.parse(_joinPath(baseUrl, '/layout_parsing'));
    final payload = {'model': model, 'file': base64Encode(imageBytes)};
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

  Future<String> _callGemini({
    required List<int> imageBytes,
    required PdfTextApiSettings settings,
  }) async {
    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.config,
        message: '请先配置 Gemini API Key',
        provider: settings.provider,
      );
    }
    final baseUrl = settings.effectiveBaseUrl();
    final model = settings.effectiveModel();
    final uri = Uri.parse(
      '${_joinPath(baseUrl, '/v1beta/models/$model:generateContent')}?key=$apiKey',
    );
    final payload = {
      'contents': [
        {
          'parts': [
            {'text': settings.prompt},
            {
              'inline_data': {
                'mime_type': 'image/png',
                'data': base64Encode(imageBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {'temperature': 0},
    };
    final resp = await _postJson(
      uri,
      payload: payload,
      provider: settings.provider,
    );
    final candidates = resp['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: 'Gemini 返回为空',
        provider: settings.provider,
      );
    }
    final content = candidates.first['content'];
    if (content is! Map<String, dynamic>) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: 'Gemini 返回格式不正确',
        provider: settings.provider,
      );
    }
    final parts = content['parts'];
    if (parts is! List) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: 'Gemini 没有识别文本',
        provider: settings.provider,
      );
    }
    final buffer = StringBuffer();
    for (final item in parts) {
      if (item is Map && item['text'] is String) {
        buffer.writeln(item['text'] as String);
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: 'Gemini 没有识别文本',
        provider: settings.provider,
      );
    }
    return text;
  }

  Future<void> _probeGemini({required PdfTextApiSettings settings}) async {
    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.config,
        message: '请先配置 Gemini API Key',
        provider: settings.provider,
      );
    }
    final baseUrl = settings.effectiveBaseUrl();
    final model = settings.effectiveModel();
    final uri = Uri.parse(
      '${_joinPath(baseUrl, '/v1beta/models/$model:generateContent')}?key=$apiKey',
    );
    final payload = {
      'contents': [
        {
          'parts': [
            {'text': 'reply ok'},
          ],
        },
      ],
      'generationConfig': {'temperature': 0},
    };
    final resp = await _postJson(
      uri,
      payload: payload,
      provider: settings.provider,
    );
    final candidates = resp['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: 'Gemini 返回为空',
        provider: settings.provider,
      );
    }
  }

  Future<String> _callTencentOcr({
    required List<int> imageBytes,
    required PdfTextApiSettings settings,
  }) async {
    final secretId = settings.secretId.trim();
    final secretKey = settings.secretKey.trim();
    if (secretId.isEmpty || secretKey.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.config,
        message: '请先配置腾讯 SecretId / SecretKey',
        provider: settings.provider,
      );
    }

    const host = 'ocr.tencentcloudapi.com';
    const service = 'ocr';
    const action = 'GeneralBasicOCR';
    const version = '2018-11-19';

    final now = DateTime.now().toUtc();
    final timestamp = (now.millisecondsSinceEpoch / 1000).floor();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final payload = jsonEncode({'ImageBase64': base64Encode(imageBytes)});

    final canonicalHeaders =
        'content-type:application/json; charset=utf-8\nhost:$host\nx-tc-action:${action.toLowerCase()}\n';
    final signedHeaders = 'content-type;host;x-tc-action';
    final canonicalRequest =
        'POST\n/\n\n$canonicalHeaders\n$signedHeaders\n${_sha256Hex(payload)}';

    final credentialScope = '$date/$service/tc3_request';
    final stringToSign =
        'TC3-HMAC-SHA256\n$timestamp\n$credentialScope\n${_sha256Hex(canonicalRequest)}';

    final secretDate = _hmacSha256(utf8.encode('TC3$secretKey'), date);
    final secretService = _hmacSha256(secretDate, service);
    final secretSigning = _hmacSha256(secretService, 'tc3_request');
    final signature = _hmacSha256Hex(secretSigning, stringToSign);

    final authorization =
        'TC3-HMAC-SHA256 Credential=$secretId/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

    final uri = Uri.parse('https://$host');
    final resp = await _postJson(
      uri,
      headers: {
        'Authorization': authorization,
        'X-TC-Action': action,
        'X-TC-Version': version,
        'X-TC-Timestamp': '$timestamp',
        'X-TC-Region': settings.tencentRegion.trim().isEmpty
            ? 'ap-beijing'
            : settings.tencentRegion.trim(),
      },
      payload: jsonDecode(payload) as Map<String, dynamic>,
      contentType: 'application/json; charset=utf-8',
      provider: settings.provider,
    );

    final response = resp['Response'];
    if (response is! Map<String, dynamic>) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: '腾讯OCR返回格式不正确',
        provider: settings.provider,
      );
    }
    final error = response['Error'];
    if (error is Map) {
      final code = error['Code']?.toString();
      final message = error['Message']?.toString() ?? '腾讯OCR调用失败';
      throw PdfOcrException(
        level: _levelFromProviderCode(code),
        message: message,
        provider: settings.provider,
        providerCode: code,
        retryable: _retryableByProviderCode(code),
      );
    }
    final textDetections = response['TextDetections'];
    if (textDetections is! List || textDetections.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: '腾讯OCR未识别到文本',
        provider: settings.provider,
      );
    }
    final lines = <String>[];
    for (final item in textDetections) {
      if (item is Map && item['DetectedText'] is String) {
        lines.add((item['DetectedText'] as String).trim());
      }
    }
    final text = lines.where((line) => line.isNotEmpty).join('\n');
    if (text.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: '腾讯OCR未识别到文本',
        provider: settings.provider,
      );
    }
    return text;
  }

  Future<String> _callBaiduOcr({
    required List<int> imageBytes,
    required PdfTextApiSettings settings,
  }) async {
    final apiKey = settings.apiKey.trim();
    final secretKey = settings.apiSecret.trim();
    if (apiKey.isEmpty || secretKey.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.config,
        message: '请先配置百度 API Key / Secret Key',
        provider: settings.provider,
      );
    }

    final authUrl = settings.baiduAuthUrl.trim().isEmpty
        ? 'https://aip.baidubce.com/oauth/2.0/token'
        : settings.baiduAuthUrl.trim();

    final tokenUri = Uri.parse(authUrl).replace(
      queryParameters: {
        'grant_type': 'client_credentials',
        'client_id': apiKey,
        'client_secret': secretKey,
      },
    );
    final tokenResp = await _postForm(
      tokenUri,
      fields: const {},
      provider: settings.provider,
    );
    final accessToken = tokenResp['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.auth,
        message: '百度 access_token 获取失败',
        provider: settings.provider,
      );
    }

    final ocrUrl = settings.baiduOcrUrl.trim().isEmpty
        ? 'https://aip.baidubce.com/rest/2.0/ocr/v1/accurate_basic'
        : settings.baiduOcrUrl.trim();
    final ocrUri = Uri.parse(
      ocrUrl,
    ).replace(queryParameters: {'access_token': accessToken});

    final ocrResp = await _postForm(
      ocrUri,
      fields: {'image': base64Encode(imageBytes)},
      provider: settings.provider,
    );

    final errorCode = ocrResp['error_code'];
    if (errorCode != null) {
      final code = errorCode.toString();
      final msg = ocrResp['error_msg']?.toString() ?? '百度OCR调用失败';
      throw PdfOcrException(
        level: _levelFromProviderCode(code),
        message: msg,
        provider: settings.provider,
        providerCode: code,
        retryable: _retryableByProviderCode(code),
      );
    }

    final wordsResult = ocrResp['words_result'];
    if (wordsResult is! List || wordsResult.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: '百度OCR未识别到文本',
        provider: settings.provider,
      );
    }
    final lines = <String>[];
    for (final item in wordsResult) {
      if (item is Map && item['words'] is String) {
        lines.add((item['words'] as String).trim());
      }
    }
    final text = lines.where((line) => line.isNotEmpty).join('\n');
    if (text.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: '百度OCR未识别到文本',
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

  Future<Map<String, dynamic>> _postForm(
    Uri uri, {
    required Map<String, String> fields,
    Map<String, String> headers = const {},
    required PdfTextApiProvider provider,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      for (final entry in headers.entries) {
        req.headers.set(entry.key, entry.value);
      }
      if (fields.isNotEmpty) {
        req.add(utf8.encode(Uri(queryParameters: fields).query));
      }
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

  String _sha256Hex(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  List<int> _hmacSha256(List<int> key, String message) {
    return Hmac(sha256, key).convert(utf8.encode(message)).bytes;
  }

  String _hmacSha256Hex(List<int> key, String message) {
    return Hmac(sha256, key).convert(utf8.encode(message)).toString();
  }

  PdfOcrErrorLevel _levelFromProviderCode(String? code) {
    if (code == null || code.isEmpty) return PdfOcrErrorLevel.request;
    final upper = code.toUpperCase();
    if (upper.contains('AUTH') || upper.contains('UNAUTHORIZED')) {
      return PdfOcrErrorLevel.auth;
    }
    if (upper.contains('LIMIT') || upper.contains('FREQUENCY')) {
      return PdfOcrErrorLevel.rateLimit;
    }
    if (upper.contains('TIMEOUT')) {
      return PdfOcrErrorLevel.timeout;
    }
    return PdfOcrErrorLevel.request;
  }

  bool _retryableByProviderCode(String? code) {
    if (code == null || code.isEmpty) return false;
    final upper = code.toUpperCase();
    return upper.contains('LIMIT') ||
        upper.contains('FREQUENCY') ||
        upper.contains('TIMEOUT') ||
        upper.contains('INTERNAL') ||
        upper.contains('SERVER');
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
