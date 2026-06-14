import 'package:flutter_test/flutter_test.dart';
import 'package:simple_reader/screens/reader/ai_chat_share_content.dart';
import 'package:simple_reader/services/ai_chat_store.dart';

void main() {
  test('builds share text from question, answer, quote and citations', () {
    const question = AiChatMessage(
      id: 'q',
      role: AiChatRole.user,
      content: '这段内容是什么意思？',
      quote: '被引用的内容',
      createdAt: 1,
    );
    const answer = AiChatMessage(
      id: 'a',
      role: AiChatRole.assistant,
      content: '## 结论\n这是 **回答**，参考 [文档](https://example.com/doc)。',
      citations: [
        AiChatCitation(title: '来源标题', url: 'https://example.com/source'),
      ],
      createdAt: 2,
    );

    final text = buildAiChatShareText(question: question, answer: answer);

    expect(text, contains('**Q：** 这段内容是什么意思？'));
    expect(text, contains('> 被引用的内容'));
    expect(text, contains('**A：**\n\n## 结论\n这是 **回答**'));
    expect(text, contains('### 参考来源'));
    expect(text, contains('[来源标题](https://example.com/source)'));
  });
}
