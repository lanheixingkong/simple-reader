import 'dart:convert';
import 'dart:io';

abstract class AgentTool {
  const AgentTool();

  String get name;
  String get description;
  Map<String, dynamic> get parameters;

  Future<AgentToolResult> execute(Map<String, dynamic> arguments);

  Map<String, dynamic> definition() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters,
      },
    };
  }
}

class AgentToolResult {
  const AgentToolResult({required this.content, this.citations = const []});

  final String content;
  final List<AgentCitation> citations;
}

class AgentCitation {
  const AgentCitation({required this.title, required this.url});

  final String title;
  final String url;
}

class TavilyWebSearchTool extends AgentTool {
  const TavilyWebSearchTool({
    required this.apiKey,
    this.maxResults = 5,
    this.baseUrl = 'https://api.tavily.com',
  });

  final String apiKey;
  final int maxResults;
  final String baseUrl;

  @override
  String get name => 'web_search';

  @override
  String get description => '搜索互联网以获取最新或外部信息。仅在问题需要联网信息时使用。';

  @override
  Map<String, dynamic> get parameters => _webSearchParameters;

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> arguments) async {
    final query = _readSearchQuery(arguments);
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const FormatException('请先配置 Tavily API Key');
    }
    final root = baseUrl.trim();
    final cleanRoot = root.endsWith('/')
        ? root.substring(0, root.length - 1)
        : root;
    final uri = Uri.parse('$cleanRoot/search');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.add(
        utf8.encode(
          jsonEncode({
            'query': query,
            'search_depth': 'basic',
            'max_results': maxResults,
            'include_answer': false,
            'include_raw_content': false,
          }),
        ),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final body = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Tavily 搜索失败（HTTP ${response.statusCode}）',
          uri: uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Tavily 返回格式不正确');
      }
      return _parseSearchResults(
        query,
        decoded['results'],
        'Tavily',
        maxResults: maxResults,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class ExaWebSearchTool extends AgentTool {
  const ExaWebSearchTool({
    required this.apiKey,
    this.maxResults = 5,
    this.baseUrl = 'https://api.exa.ai',
  });

  final String apiKey;
  final int maxResults;
  final String baseUrl;

  @override
  String get name => 'web_search';

  @override
  String get description => '搜索互联网以获取最新或外部信息。仅在问题需要联网信息时使用。';

  @override
  Map<String, dynamic> get parameters => _webSearchParameters;

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> arguments) async {
    final query = _readSearchQuery(arguments);
    final key = _requireApiKey(apiKey, 'Exa');
    final decoded = await _postSearchJson(
      baseUrl: baseUrl,
      path: '/search',
      headers: {'x-api-key': key},
      payload: {
        'query': query,
        'numResults': maxResults,
        'contents': {
          'text': {'maxCharacters': 1200},
        },
      },
      provider: 'Exa',
    );
    return _parseSearchResults(
      query,
      decoded['results'],
      'Exa',
      maxResults: maxResults,
      snippetKeys: const ['text', 'summary'],
    );
  }
}

class BraveWebSearchTool extends AgentTool {
  const BraveWebSearchTool({
    required this.apiKey,
    this.maxResults = 5,
    this.baseUrl = 'https://api.search.brave.com',
  });

  final String apiKey;
  final int maxResults;
  final String baseUrl;

  @override
  String get name => 'web_search';

  @override
  String get description => '搜索互联网以获取最新或外部信息。仅在问题需要联网信息时使用。';

  @override
  Map<String, dynamic> get parameters => _webSearchParameters;

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> arguments) async {
    final query = _readSearchQuery(arguments);
    final key = _requireApiKey(apiKey, 'Brave Search');
    final root = _cleanBaseUrl(baseUrl);
    final uri = Uri.parse(
      '$root/res/v1/web/search',
    ).replace(queryParameters: {'q': query, 'count': '$maxResults'});
    final decoded = await _getSearchJson(
      uri: uri,
      headers: {'X-Subscription-Token': key},
      provider: 'Brave Search',
    );
    final web = decoded['web'];
    return _parseSearchResults(
      query,
      web is Map ? web['results'] : null,
      'Brave Search',
      maxResults: maxResults,
      snippetKeys: const ['description'],
    );
  }
}

class SerperWebSearchTool extends AgentTool {
  const SerperWebSearchTool({
    required this.apiKey,
    this.maxResults = 5,
    this.baseUrl = 'https://google.serper.dev',
  });

  final String apiKey;
  final int maxResults;
  final String baseUrl;

  @override
  String get name => 'web_search';

  @override
  String get description => '搜索互联网以获取最新或外部信息。仅在问题需要联网信息时使用。';

  @override
  Map<String, dynamic> get parameters => _webSearchParameters;

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> arguments) async {
    final query = _readSearchQuery(arguments);
    final key = _requireApiKey(apiKey, 'Serper');
    final decoded = await _postSearchJson(
      baseUrl: baseUrl,
      path: '/search',
      headers: {'X-API-KEY': key},
      payload: {'q': query, 'num': maxResults},
      provider: 'Serper',
    );
    return _parseSearchResults(
      query,
      decoded['organic'],
      'Serper',
      maxResults: maxResults,
      urlKeys: const ['link'],
      snippetKeys: const ['snippet'],
    );
  }
}

class SearxngWebSearchTool extends AgentTool {
  const SearxngWebSearchTool({required this.baseUrl, this.maxResults = 5});

  final String baseUrl;
  final int maxResults;

  @override
  String get name => 'web_search';

  @override
  String get description => '搜索互联网以获取最新或外部信息。仅在问题需要联网信息时使用。';

  @override
  Map<String, dynamic> get parameters => _webSearchParameters;

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> arguments) async {
    final query = _readSearchQuery(arguments);
    final root = baseUrl.trim();
    if (root.isEmpty) {
      throw const FormatException('请先配置 SearXNG 实例地址');
    }
    final cleanRoot = root.endsWith('/')
        ? root.substring(0, root.length - 1)
        : root;
    final uri = Uri.parse('$cleanRoot/search').replace(
      queryParameters: {'q': query, 'format': 'json', 'language': 'all'},
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'SimpleReader/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final body = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'SearXNG 搜索失败（HTTP ${response.statusCode}）',
          uri: uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('SearXNG 返回格式不正确');
      }
      return _parseSearchResults(
        query,
        decoded['results'],
        'SearXNG',
        maxResults: maxResults,
      );
    } finally {
      client.close(force: true);
    }
  }
}

const _webSearchParameters = <String, dynamic>{
  'type': 'object',
  'properties': {
    'query': {'type': 'string', 'description': '简洁、明确的搜索关键词'},
  },
  'required': ['query'],
  'additionalProperties': false,
};

String _readSearchQuery(Map<String, dynamic> arguments) {
  final query = arguments['query']?.toString().trim() ?? '';
  if (query.isEmpty) {
    throw const FormatException('搜索关键词不能为空');
  }
  return query;
}

String _requireApiKey(String apiKey, String provider) {
  final key = apiKey.trim();
  if (key.isEmpty) {
    throw FormatException('请先配置 $provider API Key');
  }
  return key;
}

String _cleanBaseUrl(String baseUrl) {
  final root = baseUrl.trim();
  return root.endsWith('/') ? root.substring(0, root.length - 1) : root;
}

Future<Map<String, dynamic>> _postSearchJson({
  required String baseUrl,
  required String path,
  required Map<String, String> headers,
  required Map<String, dynamic> payload,
  required String provider,
}) async {
  final uri = Uri.parse('${_cleanBaseUrl(baseUrl)}$path');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client
        .postUrl(uri)
        .timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final header in headers.entries) {
      request.headers.set(header.key, header.value);
    }
    request.add(utf8.encode(jsonEncode(payload)));
    return await _readJsonResponse(request, uri, provider);
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _getSearchJson({
  required Uri uri,
  required Map<String, String> headers,
  required String provider,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final header in headers.entries) {
      request.headers.set(header.key, header.value);
    }
    return await _readJsonResponse(request, uri, provider);
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _readJsonResponse(
  HttpClientRequest request,
  Uri uri,
  String provider,
) async {
  final response = await request.close().timeout(const Duration(seconds: 30));
  final body = await utf8
      .decodeStream(response)
      .timeout(const Duration(seconds: 20));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      '$provider 搜索失败（HTTP ${response.statusCode}）',
      uri: uri,
    );
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('$provider 返回格式不正确');
  }
  return decoded;
}

AgentToolResult _parseSearchResults(
  String query,
  dynamic rawResults,
  String provider, {
  required int maxResults,
  List<String> urlKeys = const ['url'],
  List<String> snippetKeys = const ['content'],
}) {
  if (rawResults is! List) {
    throw FormatException('$provider 返回结果不正确');
  }
  final results = rawResults
      .whereType<Map>()
      .take(maxResults)
      .map((item) {
        final title = item['title']?.toString().trim() ?? '';
        final url = _firstString(item, urlKeys);
        final snippet = _firstString(item, snippetKeys);
        return {'title': title, 'url': url, 'snippet': snippet};
      })
      .where((item) => item['url']!.isNotEmpty)
      .toList();
  final citations = results
      .map(
        (item) => AgentCitation(
          title: item['title']!.isEmpty ? item['url']! : item['title']!,
          url: item['url']!,
        ),
      )
      .toList();
  return AgentToolResult(
    content: jsonEncode({'query': query, 'results': results}),
    citations: citations,
  );
}

String _firstString(Map<dynamic, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final value = item[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}
