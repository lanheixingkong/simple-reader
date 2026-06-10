import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_reader/services/agent_service.dart';
import 'package:simple_reader/services/agent_tool.dart';
import 'package:simple_reader/services/ai_chat_api_store.dart';
import 'package:simple_reader/services/ai_chat_service.dart';

void main() {
  const settings = AiChatApiSettings(
    provider: AiChatApiProvider.openai,
    baseUrl: '',
    model: '',
    apiKey: 'test',
    systemPrompt: 'help',
    temperature: 0.2,
  );

  test('executes a tool and returns citations with the final answer', () async {
    final model = _FakeAgentModel();
    final service = AgentService(
      aiChatService: model,
      toolsBuilder: (_) => const [_FakeSearchTool()],
    );

    final events = await service
        .run(settings: settings, history: const [], question: 'latest release?')
        .toList();

    expect(events.whereType<AgentStatusEvent>(), isNotEmpty);
    final completed = events.whereType<AgentCompletedEvent>().single;
    expect(completed.answer, 'final answer');
    expect(completed.citations.single.url, 'https://example.com/release');
    expect(model.requests, hasLength(2));
    expect(model.requests.last.any((item) => item['role'] == 'tool'), isTrue);
    final toolMessage = model.requests.last.firstWhere(
      (item) => item['role'] == 'tool',
    );
    expect(toolMessage['content'], contains('release result'));
  });

  test(
    'Tavily tool sends a query and returns agent-readable results',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestFuture = server.first.then((request) async {
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-key',
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'results': [
              {
                'title': 'Release notes',
                'url': 'https://example.com/release',
                'content': 'Version 2 was released today.',
              },
            ],
          }),
        );
        await request.response.close();
        return payload;
      });
      final tool = TavilyWebSearchTool(
        apiKey: 'test-key',
        baseUrl: 'http://${server.address.host}:${server.port}',
      );

      final result = await tool.execute({'query': 'latest release'});
      final requestPayload = await requestFuture;

      expect(requestPayload['query'], 'latest release');
      expect(result.content, contains('Version 2 was released today.'));
      expect(result.citations.single.url, 'https://example.com/release');
    },
  );

  test('hosted search tools normalize snippets and citations', () async {
    final cases = <_HostedSearchCase>[
      _HostedSearchCase(
        buildTool: (baseUrl) =>
            ExaWebSearchTool(apiKey: 'key', baseUrl: baseUrl),
        response: {
          'results': [
            {
              'title': 'Exa result',
              'url': 'https://example.com/exa',
              'text': 'Exa readable content',
            },
          ],
        },
        expectedContent: 'Exa readable content',
        expectedUrl: 'https://example.com/exa',
      ),
      _HostedSearchCase(
        buildTool: (baseUrl) =>
            BraveWebSearchTool(apiKey: 'key', baseUrl: baseUrl),
        response: {
          'web': {
            'results': [
              {
                'title': 'Brave result',
                'url': 'https://example.com/brave',
                'description': 'Brave readable content',
              },
            ],
          },
        },
        expectedContent: 'Brave readable content',
        expectedUrl: 'https://example.com/brave',
      ),
      _HostedSearchCase(
        buildTool: (baseUrl) =>
            SerperWebSearchTool(apiKey: 'key', baseUrl: baseUrl),
        response: {
          'organic': [
            {
              'title': 'Serper result',
              'link': 'https://example.com/serper',
              'snippet': 'Serper readable content',
            },
          ],
        },
        expectedContent: 'Serper readable content',
        expectedUrl: 'https://example.com/serper',
      ),
    ];

    for (final item in cases) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final responseFuture = server.first.then((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(item.response));
        await request.response.close();
      });
      final tool = item.buildTool(
        'http://${server.address.host}:${server.port}',
      );

      final result = await tool.execute({'query': 'test query'});
      await responseFuture;
      await server.close(force: true);

      expect(result.content, contains(item.expectedContent));
      expect(result.citations.single.url, item.expectedUrl);
    }
  });
}

class _FakeAgentModel extends AiChatService {
  final List<List<Map<String, dynamic>>> requests = [];

  @override
  Future<AgentModelResponse> agentCompletion({
    required AiChatApiSettings settings,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async {
    requests.add(messages.map(Map<String, dynamic>.from).toList());
    if (requests.length == 1) {
      return const AgentModelResponse(
        content: '',
        toolCalls: [
          AgentToolCall(
            id: 'call-1',
            name: 'web_search',
            arguments: {'query': 'latest release'},
          ),
        ],
        rawMessage: {'role': 'assistant', 'content': null, 'tool_calls': []},
      );
    }
    return const AgentModelResponse(
      content: 'final answer',
      toolCalls: [],
      rawMessage: {'role': 'assistant', 'content': 'final answer'},
    );
  }
}

class _FakeSearchTool extends AgentTool {
  const _FakeSearchTool();

  @override
  String get name => 'web_search';

  @override
  String get description => 'search';

  @override
  Map<String, dynamic> get parameters => const {'type': 'object'};

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> arguments) async {
    return const AgentToolResult(
      content: 'release result',
      citations: [
        AgentCitation(title: 'Release', url: 'https://example.com/release'),
      ],
    );
  }
}

class _HostedSearchCase {
  const _HostedSearchCase({
    required this.buildTool,
    required this.response,
    required this.expectedContent,
    required this.expectedUrl,
  });

  final AgentTool Function(String baseUrl) buildTool;
  final Map<String, dynamic> response;
  final String expectedContent;
  final String expectedUrl;
}
