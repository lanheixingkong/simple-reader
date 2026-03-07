import 'dart:convert';

import 'ai_chat_api_store.dart';
import 'ai_chat_service.dart';
import 'book_translation_cache_store.dart';

class BookTranslationService {
  BookTranslationService({AiChatService? aiChatService})
    : _aiChatService = aiChatService ?? AiChatService();

  final AiChatService _aiChatService;

  static final RegExp _cjkRegExp = RegExp(
    r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]',
  );

  bool isLikelyChinese(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final matches = _cjkRegExp.allMatches(trimmed).length;
    final letters = RegExp(r'[A-Za-z]').allMatches(trimmed).length;
    return matches >= 4 && matches >= letters;
  }

  List<String> splitParagraphs(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return const [];
    final byBlankLines = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (byBlankLines.length > 1) {
      return byBlankLines;
    }
    return normalized
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String paragraphKey(String text) {
    return BookTranslationCacheStore.paragraphKey(text);
  }

  Future<Map<String, String>> translateParagraphs({
    required AiChatApiSettings settings,
    required List<String> paragraphs,
  }) async {
    final uniqueMissing = <String>[];
    final seen = <String>{};
    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty || isLikelyChinese(trimmed)) continue;
      if (seen.add(trimmed)) {
        uniqueMissing.add(trimmed);
      }
    }
    if (uniqueMissing.isEmpty) return const {};

    final result = <String, String>{};
    for (final batch in _batches(uniqueMissing)) {
      final translatedBatch = await _translateBatch(
        settings: settings,
        batch: batch,
      );
      result.addAll(translatedBatch);
    }
    return result;
  }

  Iterable<List<String>> _batches(List<String> paragraphs) sync* {
    var current = <String>[];
    var currentChars = 0;
    for (final paragraph in paragraphs) {
      final cost = paragraph.length;
      if (current.isNotEmpty &&
          (current.length >= 12 || currentChars + cost > 4000)) {
        yield current;
        current = <String>[];
        currentChars = 0;
      }
      current.add(paragraph);
      currentChars += cost;
    }
    if (current.isNotEmpty) {
      yield current;
    }
  }

  Future<Map<String, String>> _translateBatch({
    required AiChatApiSettings settings,
    required List<String> batch,
  }) async {
    final encoded = jsonEncode([
      for (var i = 0; i < batch.length; i++) {'index': i, 'text': batch[i]},
    ]);
    try {
      final response = await _aiChatService.simpleCompletion(
        settings: settings,
        systemPrompt:
            '你是图书翻译引擎。任务是把输入的每个段落忠实翻译为简体中文。'
            '不要总结，不要省略，不要解释，不要添加前后缀。'
            '必须返回 JSON 数组；每项包含 index 和 translation 字段。',
        userPrompt:
            '把下面 JSON 数组里的每个 text 翻译为简体中文。'
            '如果原文已经是中文，translation 返回原文。'
            '保持段落顺序和 index 不变。只输出 JSON，不要 Markdown。\n$encoded',
        temperature: 0.2,
      );
      final parsed = jsonDecode(response);
      if (parsed is List) {
        final result = <String, String>{};
        for (final item in parsed) {
          if (item is! Map) continue;
          final index = item['index'];
          if (index is! int || index < 0 || index >= batch.length) continue;
          final translation = (item['translation'] ?? '').toString().trim();
          if (translation.isEmpty) continue;
          result[paragraphKey(batch[index])] = translation;
        }
        if (result.length == batch.length) {
          return result;
        }
      }
    } catch (_) {
      // Fallback below handles malformed JSON and partial responses.
    }

    final result = <String, String>{};
    for (final paragraph in batch) {
      final translation = await _aiChatService.simpleCompletion(
        settings: settings,
        systemPrompt:
            '你是图书翻译引擎。把用户提供的段落忠实翻译为简体中文。'
            '不要总结，不要解释，不要添加引号或额外说明。',
        userPrompt: '请把下面这段文字翻译为简体中文；如果原文已经是中文，原样返回：\n$paragraph',
        temperature: 0.2,
      );
      final trimmed = translation.trim();
      if (trimmed.isNotEmpty) {
        result[paragraphKey(paragraph)] = trimmed;
      }
    }
    return result;
  }
}
