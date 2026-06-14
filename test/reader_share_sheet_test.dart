import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_reader/screens/reader/reader_share_sheet.dart';

void main() {
  testWidgets('renders markdown tables as table cells', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ReaderShareSheet(
              title: 'Book',
              author: 'AI 阅读助手',
              text: '''
**A：**

| 项目 | 说明 |
| --- | --- |
| Agent | **支持**工具调用 |
| 搜索 | Tavily |
''',
              sourceLabel: '分享 AI 问答',
              messenger: ScaffoldMessenger.of(context),
              renderMarkdown: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('项目'), findsOneWidget);
    expect(find.text('说明'), findsOneWidget);
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.textContaining('| --- |'), findsNothing);
  });
}
