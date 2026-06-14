import 'book_translation_cache_store.dart';

String formatReaderSelectionForShare({
  required String selectedText,
  required List<String> sourceParagraphs,
  required Map<String, String> translations,
  required bool includeTranslations,
}) {
  final normalizedSelected = _compact(selectedText);
  if (normalizedSelected.isEmpty) return selectedText.trim();

  final blocks = <String>[];
  final compactBlocks = <String>[];
  for (final source in sourceParagraphs) {
    final paragraph = source.trim();
    if (paragraph.isEmpty) continue;
    _addBlock(blocks, compactBlocks, paragraph);
    if (!includeTranslations) continue;
    final translation =
        translations[BookTranslationCacheStore.paragraphKey(paragraph)]?.trim();
    if (translation == null ||
        translation.isEmpty ||
        translation == paragraph) {
      continue;
    }
    _addBlock(blocks, compactBlocks, translation);
  }
  if (blocks.isEmpty) return _normalizeFallback(selectedText);

  final startOffset = compactBlocks.join().indexOf(normalizedSelected);
  if (startOffset == -1) return _normalizeFallback(selectedText);
  final endOffset = startOffset + normalizedSelected.length;

  var cursor = 0;
  final selectedBlocks = <String>[];
  for (var i = 0; i < blocks.length; i++) {
    final compact = compactBlocks[i];
    final blockStart = cursor;
    final blockEnd = blockStart + compact.length;
    cursor = blockEnd;
    if (endOffset <= blockStart || startOffset >= blockEnd) continue;

    final localStart = startOffset <= blockStart ? 0 : startOffset - blockStart;
    final localEnd = endOffset >= blockEnd
        ? compact.length
        : endOffset - blockStart;
    final slice = _sliceByCompactOffsets(blocks[i], localStart, localEnd);
    if (slice.isNotEmpty) selectedBlocks.add(slice);
  }
  return selectedBlocks.isEmpty
      ? _normalizeFallback(selectedText)
      : selectedBlocks.join('\n\n');
}

void _addBlock(List<String> blocks, List<String> compactBlocks, String value) {
  final compact = _compact(value);
  if (compact.isEmpty) return;
  blocks.add(value);
  compactBlocks.add(compact);
}

String _compact(String text) => text.replaceAll(RegExp(r'\s+'), '');

String _sliceByCompactOffsets(String text, int compactStart, int compactEnd) {
  if (compactStart >= compactEnd) return '';
  var compactIndex = 0;
  int? startIndex;
  var endIndex = text.length;
  for (var i = 0; i < text.length; i++) {
    if (RegExp(r'\s').hasMatch(text[i])) continue;
    if (startIndex == null && compactIndex >= compactStart) {
      startIndex = i;
    }
    compactIndex += 1;
    if (compactIndex >= compactEnd) {
      endIndex = i + 1;
      break;
    }
  }
  if (startIndex == null) return '';
  return text.substring(startIndex, endIndex).trim();
}

String _normalizeFallback(String text) {
  return text
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n\s*\n'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .join('\n\n');
}
