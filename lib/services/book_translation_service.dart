import 'dart:async';

import 'ai_chat_api_store.dart';
import 'ai_chat_service.dart';
import 'book_translation_cache_store.dart';

class BookTranslationService {
  BookTranslationService({
    AiChatService? aiChatService,
    this.maxConcurrentTranslations = 5,
  }) : assert(maxConcurrentTranslations > 0),
       _aiChatService = aiChatService ?? AiChatService();

  final AiChatService _aiChatService;
  final int maxConcurrentTranslations;

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
    FutureOr<void> Function(String key, String translation)?
    onParagraphTranslated,
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
    Object? firstError;
    StackTrace? firstStackTrace;
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < uniqueMissing.length) {
        final paragraph = uniqueMissing[nextIndex++];
        try {
          final translation = await _translateParagraph(
            settings: settings,
            paragraph: paragraph,
          );
          if (translation.isEmpty) continue;
          final key = paragraphKey(paragraph);
          result[key] = translation;
          await onParagraphTranslated?.call(key, translation);
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
    }

    final workerCount = uniqueMissing.length < maxConcurrentTranslations
        ? uniqueMissing.length
        : maxConcurrentTranslations;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
    return result;
  }

  Future<String> _translateParagraph({
    required AiChatApiSettings settings,
    required String paragraph,
  }) async {
    final translation = await _aiChatService.simpleCompletion(
      settings: settings,
      systemPrompt:
          '你是图书翻译引擎。把用户提供的段落忠实翻译为简体中文。'
          '不要总结，不要解释，不要添加引号或额外说明。',
      userPrompt: '请把下面这段文字翻译为简体中文；如果原文已经是中文，原样返回：\n$paragraph',
      temperature: 0.2,
    );
    return translation.trim();
  }
}
