import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/library.dart';
import '../../services/ai_chat_api_store.dart';
import '../../services/ai_chat_service.dart';
import '../../services/ai_chat_store.dart';
import 'ai_chat_api_settings_sheet.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key, required this.book, this.initialQuote});

  final Book book;
  final String? initialQuote;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _apiStore = AiChatApiStore.instance;
  final _chatStore = AiChatStore.instance;
  final _service = AiChatService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  AiChatApiSettings? _settings;
  List<AiChatConversation> _allConversations = [];
  AiChatConversation? _currentConversation;
  String? _pendingQuote;
  bool _sending = false;
  String? _errorText;
  String _streamingAssistantText = '';

  @override
  void initState() {
    super.initState();
    _pendingQuote = widget.initialQuote?.trim().isEmpty ?? true
        ? null
        : widget.initialQuote!.trim();
    _load();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _apiStore.load();
    final all = await _chatStore.loadAll();
    final current = _pickInitialConversation(all);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _allConversations = all;
      _currentConversation = current;
    });
    _scrollToBottom();
  }

  AiChatConversation _pickInitialConversation(List<AiChatConversation> all) {
    final scoped = _scopedConversations(all);
    if (scoped.isNotEmpty) return scoped.first;
    final now = DateTime.now().millisecondsSinceEpoch;
    return AiChatConversation(
      id: 'chat-$now',
      title: '新对话',
      bookId: widget.book.id,
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
  }

  List<AiChatConversation> _scopedConversations(List<AiChatConversation> all) {
    final scoped = all.where((item) => item.bookId == widget.book.id).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return scoped;
  }

  Future<void> _saveCurrent(AiChatConversation conversation) async {
    final index = _allConversations.indexWhere(
      (item) => item.id == conversation.id,
    );
    if (index >= 0) {
      _allConversations[index] = conversation;
    } else {
      _allConversations.add(conversation);
    }
    _allConversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _chatStore.saveAll(_allConversations);
  }

  Future<void> _createConversation() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final conversation = AiChatConversation(
      id: 'chat-$now',
      title: '新对话',
      bookId: widget.book.id,
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
    await _saveCurrent(conversation);
    if (!mounted) return;
    setState(() {
      _currentConversation = conversation;
      _errorText = null;
    });
  }

  Future<void> _deleteConversation(AiChatConversation conversation) async {
    _allConversations.removeWhere((item) => item.id == conversation.id);
    await _chatStore.saveAll(_allConversations);
    if (!mounted) return;
    setState(() {
      if (_currentConversation?.id == conversation.id) {
        final scoped = _scopedConversations(_allConversations);
        _currentConversation = scoped.isNotEmpty
            ? scoped.first
            : _pickInitialConversation(_allConversations);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final current = _currentConversation;
    if (settings == null || current == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scopedConversations = _scopedConversations(_allConversations);
    return Scaffold(
      appBar: AppBar(
        title: Text(current.title),
        actions: [
          IconButton(
            onPressed: _createConversation,
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '新建对话',
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: '接口设置',
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: const Text('对话列表'),
                trailing: IconButton(
                  onPressed: _createConversation,
                  icon: const Icon(Icons.add),
                  tooltip: '新建',
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: scopedConversations.isEmpty
                    ? const Center(child: Text('暂无对话'))
                    : ListView.builder(
                        itemCount: scopedConversations.length,
                        itemBuilder: (context, index) {
                          final item = scopedConversations[index];
                          return Dismissible(
                            key: ValueKey<String>('conv-${item.id}'),
                            background: Container(
                              alignment: Alignment.centerRight,
                              color: Colors.redAccent,
                              padding: const EdgeInsets.only(right: 16),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) => _deleteConversation(item),
                            child: ListTile(
                              selected: item.id == _currentConversation?.id,
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                _conversationSubtitle(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.of(context).pop();
                                setState(() {
                                  _currentConversation = item;
                                  _errorText = null;
                                });
                                _scrollToBottom();
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_errorText != null)
            Material(
              color: Colors.red.shade50,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    _errorText!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ),
            ),
          Expanded(child: _buildMessageList(current)),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageList(AiChatConversation conversation) {
    final hasStreaming = _streamingAssistantText.trim().isNotEmpty;
    if (conversation.messages.isEmpty && !hasStreaming && !_sending) {
      return Center(
        child: Text(
          _pendingQuote == null ? '开始提问吧' : '引用内容已带入，可直接提问',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      itemCount:
          conversation.messages.length + ((_sending || hasStreaming) ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == conversation.messages.length &&
            (_sending || hasStreaming)) {
          return _buildBubble(isUser: false, content: _streamingAssistantText);
        }
        final message = conversation.messages[index];
        return _buildBubble(
          isUser: message.role == AiChatRole.user,
          content: message.content,
          quote: message.quote,
        );
      },
    );
  }

  Widget _buildBubble({
    required bool isUser,
    required String content,
    String? quote,
  }) {
    final bubbleColor = isUser
        ? const Color(0xFFE6F4FF)
        : const Color(0xFFF1F3F5);
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final radius = BorderRadius.circular(12);
    final textColor = Colors.black.withValues(alpha: 0.88);
    return Align(
      alignment: align,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (isUser && (quote?.trim().isNotEmpty ?? false))
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  quote!.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade800,
                    height: 1.45,
                  ),
                ),
              ),
            if (isUser)
              Text(content, style: const TextStyle(height: 1.5))
            else
              MarkdownBody(
                data: content.isEmpty ? '...' : content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(height: 1.5, color: textColor, fontSize: 15),
                  code: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Colors.black.withValues(alpha: 0.82),
                  ),
                  blockquote: TextStyle(
                    color: Colors.black.withValues(alpha: 0.72),
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingQuote != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE9ECEF)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.format_quote, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _pendingQuote!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _pendingQuote = null),
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: '移除引用',
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: '输入问题...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: const Text('发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final settings = _settings;
    var conversation = _currentConversation;
    if (settings == null || conversation == null || _sending) return;
    final question = _inputController.text.trim();
    if (question.isEmpty) return;

    _inputController.clear();
    final now = DateTime.now().millisecondsSinceEpoch;
    final quote = _pendingQuote?.trim();
    _pendingQuote = null;
    final userMessage = AiChatMessage(
      id: 'msg-u-$now',
      role: AiChatRole.user,
      content: question,
      quote: quote?.isEmpty ?? true ? null : quote,
      createdAt: now,
    );
    final beforeHistory = List<AiChatMessage>.from(conversation.messages);
    final updatedMessages = List<AiChatMessage>.from(conversation.messages)
      ..add(userMessage);
    conversation = conversation.copyWith(
      title: _buildConversationTitle(conversation, question),
      updatedAt: now,
      messages: updatedMessages,
    );
    await _saveCurrent(conversation);
    if (!mounted) return;
    setState(() {
      _currentConversation = conversation;
      _sending = true;
      _errorText = null;
      _streamingAssistantText = '';
    });
    _scrollToBottom();

    try {
      await for (final delta in _service.streamChatCompletion(
        settings: settings,
        history: beforeHistory,
        question: question,
        quote: quote,
      )) {
        if (!mounted) return;
        setState(() {
          _streamingAssistantText += delta;
        });
        _scrollToBottom();
      }
      final answer = _streamingAssistantText.trim();
      if (answer.isEmpty) {
        throw AiChatException(
          level: AiChatErrorLevel.response,
          message: '模型没有返回文本内容',
          provider: settings.provider,
        );
      }
      final assistantMessage = AiChatMessage(
        id: 'msg-a-${DateTime.now().millisecondsSinceEpoch}',
        role: AiChatRole.assistant,
        content: answer,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      final completedConversation = conversation.copyWith(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        messages: List<AiChatMessage>.from(conversation.messages)
          ..add(assistantMessage),
      );
      await _saveCurrent(completedConversation);
      if (!mounted) return;
      setState(() {
        _currentConversation = completedConversation;
        _streamingAssistantText = '';
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error is AiChatException
            ? error.userMessage()
            : '请求失败：$error';
        _streamingAssistantText = '';
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  String _buildConversationTitle(
    AiChatConversation conversation,
    String question,
  ) {
    if (conversation.messages.isNotEmpty || conversation.title != '新对话') {
      return conversation.title;
    }
    final trimmed = question.trim();
    if (trimmed.isEmpty) return conversation.title;
    if (trimmed.length <= 16) return trimmed;
    return '${trimmed.substring(0, 16)}...';
  }

  String _conversationSubtitle(AiChatConversation conversation) {
    if (conversation.messages.isEmpty) return '暂无消息';
    final last = conversation.messages.last;
    return last.content.replaceAll('\n', ' ');
  }

  Future<void> _openSettings() async {
    final current = _settings ?? await _apiStore.load();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: AiChatApiSettingsSheet(
          initial: current,
          onSave: (updated) async {
            await _apiStore.save(updated);
            if (!mounted) return;
            setState(() => _settings = updated);
          },
          onTest: _testSettings,
        ),
      ),
    );
  }

  Future<String> _testSettings(AiChatApiSettings settings) {
    return _service.testSettings(settings: settings);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }
}
