import 'package:flutter_test/flutter_test.dart';
import 'package:simple_reader/services/book_translation_cache_store.dart';
import 'package:simple_reader/services/reader_selection_share_formatter.dart';

void main() {
  const first = 'First paragraph.';
  const second = 'Second paragraph.';
  final translations = <String, String>{
    BookTranslationCacheStore.paragraphKey(first): '第一段。',
    BookTranslationCacheStore.paragraphKey(second): '第二段。',
  };

  test('restores paragraph boundaries when translations are visible', () {
    final result = formatReaderSelectionForShare(
      selectedText: '$first第一段。$second第二段。',
      sourceParagraphs: const [first, second],
      translations: translations,
      includeTranslations: true,
    );

    expect(result, '$first\n\n第一段。\n\n$second\n\n第二段。');
  });

  test('restores boundaries for a partial multi-block selection', () {
    final result = formatReaderSelectionForShare(
      selectedText: 'paragraph.第一段。Second',
      sourceParagraphs: const [first, second],
      translations: translations,
      includeTranslations: true,
    );

    expect(result, 'paragraph.\n\n第一段。\n\nSecond');
  });

  test('does not include translations when they are hidden', () {
    final result = formatReaderSelectionForShare(
      selectedText: '$first$second',
      sourceParagraphs: const [first, second],
      translations: translations,
      includeTranslations: false,
    );

    expect(result, '$first\n\n$second');
  });
}
