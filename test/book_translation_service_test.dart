import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_reader/services/ai_chat_api_store.dart';
import 'package:simple_reader/services/ai_chat_service.dart';
import 'package:simple_reader/services/book_translation_service.dart';

void main() {
  const settings = AiChatApiSettings(
    provider: AiChatApiProvider.openai,
    baseUrl: '',
    model: '',
    apiKey: '',
    systemPrompt: '',
    temperature: 0.2,
  );

  test('translates paragraphs separately with limited concurrency', () async {
    final aiChatService = _FakeAiChatService();
    final service = BookTranslationService(aiChatService: aiChatService);
    final callbacks = <String>[];

    final result = await service.translateParagraphs(
      settings: settings,
      paragraphs: const [
        'first paragraph',
        'second paragraph',
        'third paragraph',
        'fourth paragraph',
        'fifth paragraph',
      ],
      onParagraphTranslated: (_, translation) {
        callbacks.add(translation);
      },
    );

    expect(aiChatService.maxActiveRequests, 5);
    expect(aiChatService.requestedParagraphs, hasLength(5));
    expect(callbacks, hasLength(5));
    expect(result.values, containsAll(callbacks));
  });

  test(
    'reports successful paragraphs before all translations finish',
    () async {
      final firstFinished = Completer<void>();
      final releaseRemaining = Completer<void>();
      final aiChatService = _ControlledAiChatService(
        firstFinished: firstFinished,
        releaseRemaining: releaseRemaining,
      );
      final service = BookTranslationService(
        aiChatService: aiChatService,
        maxConcurrentTranslations: 2,
      );
      final callbacks = <String>[];

      final translation = service.translateParagraphs(
        settings: settings,
        paragraphs: const ['fast paragraph', 'slow paragraph'],
        onParagraphTranslated: (_, value) {
          callbacks.add(value);
        },
      );

      await firstFinished.future;
      await Future<void>.delayed(Duration.zero);
      expect(callbacks, ['translated: fast paragraph']);

      releaseRemaining.complete();
      await translation;
      expect(callbacks, hasLength(2));
    },
  );

  test('continues translating other paragraphs after one fails', () async {
    final aiChatService = _FailingAiChatService();
    final service = BookTranslationService(
      aiChatService: aiChatService,
      maxConcurrentTranslations: 2,
    );
    final callbacks = <String>[];

    await expectLater(
      service.translateParagraphs(
        settings: settings,
        paragraphs: const [
          'first paragraph',
          'failing paragraph',
          'last paragraph',
        ],
        onParagraphTranslated: (_, translation) {
          callbacks.add(translation);
        },
      ),
      throwsStateError,
    );

    expect(
      callbacks,
      containsAll([
        'translated: first paragraph',
        'translated: last paragraph',
      ]),
    );
    expect(callbacks, isNot(contains('translated: failing paragraph')));
  });
}

class _FakeAiChatService extends AiChatService {
  int activeRequests = 0;
  int maxActiveRequests = 0;
  final List<String> requestedParagraphs = [];

  @override
  Future<String> simpleCompletion({
    required AiChatApiSettings settings,
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.2,
  }) async {
    final paragraph = userPrompt.split('\n').last;
    requestedParagraphs.add(paragraph);
    activeRequests += 1;
    if (activeRequests > maxActiveRequests) {
      maxActiveRequests = activeRequests;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    activeRequests -= 1;
    return 'translated: $paragraph';
  }
}

class _ControlledAiChatService extends AiChatService {
  _ControlledAiChatService({
    required this.firstFinished,
    required this.releaseRemaining,
  });

  final Completer<void> firstFinished;
  final Completer<void> releaseRemaining;

  @override
  Future<String> simpleCompletion({
    required AiChatApiSettings settings,
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.2,
  }) async {
    final paragraph = userPrompt.split('\n').last;
    if (paragraph == 'fast paragraph') {
      firstFinished.complete();
    } else {
      await releaseRemaining.future;
    }
    return 'translated: $paragraph';
  }
}

class _FailingAiChatService extends AiChatService {
  @override
  Future<String> simpleCompletion({
    required AiChatApiSettings settings,
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.2,
  }) async {
    final paragraph = userPrompt.split('\n').last;
    if (paragraph == 'failing paragraph') {
      throw StateError('translation failed');
    }
    return 'translated: $paragraph';
  }
}
