import '../../services/ai_chat_store.dart';

String buildAiChatShareText({
  required AiChatMessage question,
  required AiChatMessage answer,
}) {
  final blocks = <String>[
    '**Q：** ${question.content.trim()}',
    if (question.quote?.trim().isNotEmpty ?? false)
      '> ${question.quote!.trim().replaceAll('\n', '\n> ')}',
    '**A：**\n\n${answer.content.trim()}',
  ];
  if (answer.citations.isNotEmpty) {
    final sources = <String>[];
    for (var i = 0; i < answer.citations.length; i++) {
      final citation = answer.citations[i];
      final title = citation.title.trim();
      final url = citation.url.trim();
      if (url.isEmpty) continue;
      sources.add('${i + 1}. [${title.isEmpty ? url : title}]($url)');
    }
    if (sources.isNotEmpty) {
      blocks.add('### 参考来源\n${sources.join('\n')}');
    }
  }
  return blocks.join('\n\n');
}
