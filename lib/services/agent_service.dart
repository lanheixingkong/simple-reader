import 'agent_tool.dart';
import 'ai_chat_api_store.dart';
import 'ai_chat_service.dart';
import 'ai_chat_store.dart';

sealed class AgentEvent {
  const AgentEvent();
}

class AgentStatusEvent extends AgentEvent {
  const AgentStatusEvent(this.message);

  final String message;
}

class AgentCompletedEvent extends AgentEvent {
  const AgentCompletedEvent({required this.answer, required this.citations});

  final String answer;
  final List<AgentCitation> citations;
}

class AgentService {
  AgentService({
    AiChatService? aiChatService,
    this.maxSteps = 6,
    this.toolsBuilder,
  }) : _aiChatService = aiChatService ?? AiChatService();

  final AiChatService _aiChatService;
  final int maxSteps;
  final List<AgentTool> Function(AiChatApiSettings settings)? toolsBuilder;

  Stream<AgentEvent> run({
    required AiChatApiSettings settings,
    required List<AiChatMessage> history,
    required String question,
    String? quote,
  }) async* {
    if (toolsBuilder == null && settings.webSearchEnabled) {
      final missingConfig = switch (settings.webSearchProvider) {
        WebSearchProvider.tavily ||
        WebSearchProvider.exa ||
        WebSearchProvider.brave ||
        WebSearchProvider.serper => settings.webSearchApiKey.trim().isEmpty,
        WebSearchProvider.searxng => settings.webSearchBaseUrl.trim().isEmpty,
      };
      if (missingConfig) {
        final name = switch (settings.webSearchProvider) {
          WebSearchProvider.tavily ||
          WebSearchProvider.exa ||
          WebSearchProvider.brave ||
          WebSearchProvider.serper => '搜索服务 API Key',
          WebSearchProvider.searxng => 'SearXNG 实例地址',
        };
        throw AiChatException(
          level: AiChatErrorLevel.config,
          message: '已启用联网搜索，但尚未配置 $name',
          provider: settings.provider,
        );
      }
    }
    final tools =
        toolsBuilder?.call(settings) ??
        <AgentTool>[
          if (settings.webSearchEnabled)
            switch (settings.webSearchProvider) {
              WebSearchProvider.tavily => TavilyWebSearchTool(
                apiKey: settings.webSearchApiKey,
              ),
              WebSearchProvider.exa => ExaWebSearchTool(
                apiKey: settings.webSearchApiKey,
              ),
              WebSearchProvider.brave => BraveWebSearchTool(
                apiKey: settings.webSearchApiKey,
              ),
              WebSearchProvider.serper => SerperWebSearchTool(
                apiKey: settings.webSearchApiKey,
              ),
              WebSearchProvider.searxng => SearxngWebSearchTool(
                baseUrl: settings.webSearchBaseUrl,
              ),
            },
        ];
    final messages = _buildMessages(settings, history, question, quote);
    final citations = <String, AgentCitation>{};

    for (var step = 0; step < maxSteps; step += 1) {
      yield AgentStatusEvent(step == 0 ? '正在分析问题' : '正在整理工具结果');
      final response = await _aiChatService.agentCompletion(
        settings: settings,
        messages: messages,
        tools: tools.map((tool) => tool.definition()).toList(),
      );
      if (response.toolCalls.isEmpty) {
        final answer = response.content.trim();
        if (answer.isEmpty) {
          throw AiChatException(
            level: AiChatErrorLevel.response,
            message: '模型没有返回最终回答',
            provider: settings.provider,
          );
        }
        yield AgentCompletedEvent(
          answer: answer,
          citations: citations.values.toList(),
        );
        return;
      }

      messages.add(response.rawMessage);
      for (final call in response.toolCalls) {
        final tool = tools.where((item) => item.name == call.name).firstOrNull;
        if (tool == null) {
          messages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': '工具 ${call.name} 不可用',
          });
          continue;
        }
        final query = call.arguments['query']?.toString().trim();
        yield AgentStatusEvent(
          query == null || query.isEmpty ? '正在执行 ${tool.name}' : '正在搜索：$query',
        );
        try {
          final result = await tool.execute(call.arguments);
          for (final citation in result.citations) {
            citations[citation.url] = citation;
          }
          messages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': result.content,
          });
          yield AgentStatusEvent('已获得 ${result.citations.length} 条搜索结果');
        } catch (error) {
          messages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': '工具执行失败：$error',
          });
          yield AgentStatusEvent('搜索失败，正在让模型调整回答');
        }
      }
    }
    throw AiChatException(
      level: AiChatErrorLevel.response,
      message: 'Agent 执行步骤过多，已停止',
      provider: settings.provider,
    );
  }

  List<Map<String, dynamic>> _buildMessages(
    AiChatApiSettings settings,
    List<AiChatMessage> history,
    String question,
    String? quote,
  ) {
    final messages = <Map<String, dynamic>>[];
    final systemPrompt = settings.systemPrompt.trim();
    if (systemPrompt.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content':
            '$systemPrompt\n\n你可以自主决定是否使用提供的工具。使用联网搜索后，回答中应引用来源链接；不要描述内部工具调用过程。',
      });
    }
    for (final item in history) {
      messages.add({
        'role': item.role == AiChatRole.user ? 'user' : 'assistant',
        'content': item.role == AiChatRole.user
            ? _buildPrompt(item.content, item.quote)
            : item.content,
      });
    }
    messages.add({'role': 'user', 'content': _buildPrompt(question, quote)});
    return messages;
  }

  String _buildPrompt(String question, String? quote) {
    final trimmedQuote = quote?.trim() ?? '';
    if (trimmedQuote.isEmpty) return question.trim();
    return '【引用开始】\n$trimmedQuote\n【引用结束】\n\n请基于上述引用内容回答：\n${question.trim()}';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
