import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ReaderShareSheet extends StatefulWidget {
  const ReaderShareSheet({
    super.key,
    required this.title,
    required this.author,
    required this.text,
    required this.sourceLabel,
    required this.messenger,
    this.renderMarkdown = false,
  });

  final String title;
  final String author;
  final String text;
  final String sourceLabel;
  final ScaffoldMessengerState messenger;
  final bool renderMarkdown;

  @override
  State<ReaderShareSheet> createState() => _ReaderShareSheetState();
}

class _ReaderShareSheetState extends State<ReaderShareSheet> {
  static const double _maxImageHeightPx = 12000;
  static const double _cardHorizontalPadding = 24;
  static const double _cardVerticalPadding = 24;
  static const double _footerTopSpacing = 12;
  static const double _footerDividerSpacing = 8;
  static const double _footerTitleSpacing = 4;
  static const double _paragraphSpacing = 12;
  static const double _tableCellPadding = 6;
  static const double _bodyFontSize = 14;
  static const double _footerTitleFontSize = 12;
  static const double _footerAuthorFontSize = 11;
  static const double _tableFontSize = 11;
  static const double _codeBlockFontSize = 11;

  bool _busy = false;
  int _templateIndex = 0;
  int _currentPage = 0;
  Size? _lastLayoutSize;
  List<List<String>> _pages = const [];
  final PageController _pageController = PageController();
  OverlayEntry? _toastEntry;

  List<_ShareTemplate> get _templates => const [
    _ShareTemplate(
      background: Color(0xFFF7F3EC),
      textColor: Color(0xFF2B231D),
      accentColor: Color(0xFFB9ADA3),
    ),
    _ShareTemplate(
      background: Color(0xFF1E1C1A),
      textColor: Color(0xFFF6F3EE),
      accentColor: Color(0xFF8D857E),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final template = _templates[_templateIndex % _templates.length];
    final size = MediaQuery.of(context).size;
    final cardWidth = (size.width - 48).clamp(240.0, 420.0);
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final maxCardHeight = _maxImageHeightPx / pixelRatio;
    _ensurePagedText(size, cardWidth, maxCardHeight);
    return SafeArea(
      child: Container(
        color: const Color(0xFFF2F1ED),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.sourceLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _buildPreview(
                    size,
                    cardWidth,
                    template,
                    maxCardHeight,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ShareActionButton(
                    icon: Icons.layers_outlined,
                    label: '更换模板',
                    onTap: _busy ? null : _cycleTemplate,
                  ),
                  _ShareActionButton(
                    icon: Icons.download,
                    label: '保存到相册',
                    onTap: _busy ? null : _saveImage,
                  ),
                  _ShareActionButton(
                    icon: Icons.chat_bubble_outline,
                    label: '分享给朋友',
                    onTap: _busy ? null : _shareImage,
                  ),
                  _ShareActionButton(
                    icon: Icons.photo_outlined,
                    label: '分享朋友圈',
                    onTap: _busy ? null : _shareImage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(
    Size size,
    double cardWidth,
    _ShareTemplate template,
    double maxCardHeight,
  ) {
    if (_pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final pages = _pages;
    final previewHeight = (size.height * 0.62).clamp(260.0, 640.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pages.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${_currentPage + 1}/${pages.length}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        SizedBox(
          height: previewHeight,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: pages.length,
            itemBuilder: (context, index) {
              final cardHeight = _cardHeightForText(
                pages[index],
                cardWidth,
                template,
                maxCardHeight,
              );
              return Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: cardWidth,
                    height: cardHeight,
                    child: _buildShareCard(
                      pages[index],
                      template,
                      cardWidth,
                      maxCardHeight,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildShareCard(
    List<String> paragraphs,
    _ShareTemplate template,
    double cardWidth,
    double maxCardHeight,
  ) {
    final contentHeight = _cardHeightForText(
      paragraphs,
      cardWidth,
      template,
      maxCardHeight,
    );
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: const TextScaler.linear(1.0)),
      child: Container(
        width: cardWidth,
        height: contentHeight,
        decoration: BoxDecoration(
          color: template.background,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: _cardHorizontalPadding,
          vertical: _cardVerticalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < paragraphs.length; i++) ...[
              if (_parseMarkdownTable(paragraphs[i]) case final table?)
                _buildMarkdownTable(table, template)
              else
                Text.rich(
                  _shareTextSpan(
                    paragraphs[i],
                    TextStyle(
                      fontSize: _bodyFontSize,
                      height: 1.7,
                      color: template.textColor,
                    ),
                  ),
                ),
              if (i < paragraphs.length - 1)
                const SizedBox(height: _paragraphSpacing),
            ],
            const SizedBox(height: _footerTopSpacing),
            Container(
              height: 1,
              color: template.accentColor.withValues(alpha: 0.6),
            ),
            const SizedBox(height: _footerDividerSpacing),
            Text(
              '《${widget.title}》',
              style: TextStyle(
                fontSize: _footerTitleFontSize,
                fontWeight: FontWeight.w600,
                color: template.textColor.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: _footerTitleSpacing),
            Text(
              widget.author,
              style: TextStyle(
                fontSize: _footerAuthorFontSize,
                color: template.textColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _cycleTemplate() {
    setState(() {
      _templateIndex = (_templateIndex + 1) % _templates.length;
    });
  }

  Future<void> _shareImage() async {
    final images = await _capturePages();
    if (images.isEmpty) {
      _showSnack('生成分享图失败');
      return;
    }
    final files = await _writeShareFiles(images);
    if (files.isEmpty) {
      _showSnack('写入分享图片失败');
      return;
    }
    if (!mounted) return;
    final shareOrigin = _sharePositionOrigin();
    final navigator = Navigator.of(context);
    navigator.pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      await Share.shareXFiles(
        files.map((file) => XFile(file.path)).toList(),
        text: '${widget.title} · ${widget.author}',
        subject: widget.title,
        sharePositionOrigin: shareOrigin,
      );
    } catch (_) {
      _showToast('系统分享面板打开失败');
    }
  }

  Future<void> _saveImage() async {
    if (kIsWeb) {
      _showSnack('当前平台暂不支持保存到相册');
      return;
    }
    final images = await _capturePages();
    if (images.isEmpty) {
      _showSnack('生成图片失败');
      return;
    }
    var successCount = 0;
    for (var i = 0; i < images.length; i++) {
      final name = 'reader-share-${DateTime.now().millisecondsSinceEpoch}-$i';
      final result = await ImageGallerySaver.saveImage(
        images[i],
        quality: 100,
        name: name,
      );
      if (result is Map && (result['isSuccess'] == true)) {
        successCount += 1;
      }
    }
    if (successCount == images.length) {
      _showSnack('已保存到相册（$successCount 张）');
    } else if (successCount > 0) {
      _showSnack('部分图片保存成功（$successCount/${images.length}）');
    } else {
      _showSnack('保存失败，请检查权限');
    }
  }

  Future<List<Uint8List>> _capturePages() async {
    if (_busy) return [];
    setState(() => _busy = true);
    try {
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final results = <Uint8List>[];
      for (var i = 0; i < _pages.length; i++) {
        if (!mounted) break;
        final bytes = await _renderShareImage(
          _pages[i],
          _templates[_templateIndex % _templates.length],
          pixelRatio,
        );
        if (bytes != null) {
          results.add(bytes);
        }
      }
      return results;
    } catch (_) {
      return [];
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<List<File>> _writeShareFiles(List<Uint8List> bytesList) async {
    final files = <File>[];
    try {
      final dir = await getTemporaryDirectory();
      for (var i = 0; i < bytesList.length; i++) {
        final jpegBytes = _encodeJpeg(bytesList[i]);
        if (jpegBytes == null) continue;
        final file = File(
          p.join(
            dir.path,
            'reader-share-${DateTime.now().millisecondsSinceEpoch}-$i.jpg',
          ),
        );
        await file.writeAsBytes(jpegBytes);
        files.add(file);
      }
      return files;
    } catch (_) {
      return [];
    }
  }

  Uint8List? _encodeJpeg(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    return Uint8List.fromList(img.encodeJpg(image, quality: 82));
  }

  Rect _sharePositionOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(0, 0, size.width, size.height);
  }

  void _ensurePagedText(Size size, double cardWidth, double maxCardHeight) {
    if (_lastLayoutSize == size && _pages.isNotEmpty) return;
    _lastLayoutSize = size;
    final pages = _paginateText(
      _normalizeShareText(widget.text),
      cardWidth,
      maxCardHeight,
    );
    _pages = pages.isEmpty
        ? const [
            [''],
          ]
        : pages;
    _currentPage = 0;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  List<List<String>> _paginateText(
    String text,
    double cardWidth,
    double maxCardHeight,
  ) {
    if (text.isEmpty) {
      return const [
        [''],
      ];
    }
    const textStyle = TextStyle(fontSize: _bodyFontSize, height: 1.7);
    const titleStyle = TextStyle(
      fontSize: _footerTitleFontSize,
      fontWeight: FontWeight.w600,
    );
    const authorStyle = TextStyle(fontSize: _footerAuthorFontSize);
    final textWidth = cardWidth - _cardHorizontalPadding * 2;
    final footerHeight = _measureFooterHeight(
      textWidth,
      titleStyle,
      authorStyle,
    );
    final maxTextHeight =
        (maxCardHeight - _cardVerticalPadding * 2 - footerHeight).clamp(
          80.0,
          maxCardHeight,
        );
    final paragraphs = _shareParagraphs(text);
    if (paragraphs.isEmpty) {
      return const [
        [''],
      ];
    }
    final pages = <List<String>>[];
    var currentPage = <String>[];
    for (final paragraph in paragraphs) {
      final candidate = [...currentPage, paragraph];
      if (_measureTextHeight(candidate, textWidth, textStyle) <=
          maxTextHeight) {
        currentPage = candidate;
        continue;
      }

      if (currentPage.isNotEmpty) {
        pages.add(currentPage);
        currentPage = [];
      }

      if (_measureTextHeight(paragraph, textWidth, textStyle) <=
          maxTextHeight) {
        currentPage = [paragraph];
        continue;
      }

      var remaining = paragraph;
      while (remaining.isNotEmpty) {
        final splitIndex = _bestFitIndex(
          remaining,
          textWidth,
          textStyle,
          maxTextHeight,
        );
        final pageText = remaining.substring(0, splitIndex).trimRight();
        if (pageText.isNotEmpty) {
          pages.add([pageText]);
        }
        remaining = remaining.substring(splitIndex).trimLeft();
      }
    }
    if (currentPage.isNotEmpty) {
      pages.add(currentPage);
    }
    return pages;
  }

  int _bestFitIndex(
    String text,
    double maxWidth,
    TextStyle style,
    double maxHeight,
  ) {
    var low = 1;
    var high = text.length;
    var best = 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final candidate = text.substring(0, mid);
      final height = _measureTextHeight(candidate, maxWidth, style);
      if (height <= maxHeight) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return _preferBreakPoint(text, best);
  }

  int _preferBreakPoint(String text, int index) {
    if (index >= text.length) return text.length;
    const separators = {'\n', ' ', '，', '。', '！', '？', '；', '：', '、'};
    for (var i = index; i > 1; i--) {
      if (separators.contains(text[i - 1])) {
        return i;
      }
    }
    return index;
  }

  String _normalizeShareText(String text) {
    var normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    normalized = normalized.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    normalized = normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return normalized.trim();
  }

  double _measureTextHeight(Object content, double maxWidth, TextStyle style) {
    if (content is List<String>) {
      var totalHeight = 0.0;
      for (var i = 0; i < content.length; i++) {
        totalHeight += _measureParagraphHeight(content[i], maxWidth, style);
        if (i < content.length - 1) {
          totalHeight += _paragraphSpacing;
        }
      }
      return totalHeight;
    }
    return _measureParagraphHeight(content as String, maxWidth, style);
  }

  double _measureParagraphHeight(
    String text,
    double maxWidth,
    TextStyle style,
  ) {
    final table = _parseMarkdownTable(text);
    if (table != null) {
      return _measureMarkdownTableHeight(table, maxWidth, style);
    }
    final painter = TextPainter(
      text: _shareTextSpan(text, style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  double _measureFooterHeight(
    double maxWidth,
    TextStyle titleStyle,
    TextStyle authorStyle,
  ) {
    final titlePainter = TextPainter(
      text: TextSpan(text: '《${widget.title}》', style: titleStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final authorPainter = TextPainter(
      text: TextSpan(text: widget.author, style: authorStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return _footerTopSpacing +
        1 +
        _footerDividerSpacing +
        titlePainter.height +
        _footerTitleSpacing +
        authorPainter.height;
  }

  double _cardHeightForText(
    List<String> paragraphs,
    double cardWidth,
    _ShareTemplate template,
    double maxCardHeight,
  ) {
    final textWidth = cardWidth - _cardHorizontalPadding * 2;
    final textHeight = _measureTextHeight(
      paragraphs,
      textWidth,
      TextStyle(
        fontSize: _bodyFontSize,
        height: 1.7,
        color: template.textColor,
      ),
    );
    final footerHeight = _measureFooterHeight(
      textWidth,
      TextStyle(
        fontSize: _footerTitleFontSize,
        fontWeight: FontWeight.w600,
        color: template.textColor.withValues(alpha: 0.85),
      ),
      TextStyle(
        fontSize: _footerAuthorFontSize,
        color: template.textColor.withValues(alpha: 0.7),
      ),
    );
    final targetHeight = _cardVerticalPadding * 2 + textHeight + footerHeight;
    return targetHeight.clamp(260.0, maxCardHeight);
  }

  Future<Uint8List?> _renderShareImage(
    List<String> paragraphs,
    _ShareTemplate template,
    double pixelRatio,
  ) async {
    final size = MediaQuery.of(context).size;
    final cardWidth = (size.width - 48).clamp(240.0, 420.0);
    final maxCardHeight = _maxImageHeightPx / pixelRatio;
    final cardHeight = _cardHeightForText(
      paragraphs,
      cardWidth,
      template,
      maxCardHeight,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    final rect = Rect.fromLTWH(0, 0, cardWidth, cardHeight);
    final paint = Paint()..color = template.background;
    canvas.drawRect(rect, paint);
    final textWidth = cardWidth - _cardHorizontalPadding * 2;
    final textOffset = Offset(_cardHorizontalPadding, _cardVerticalPadding);
    var paragraphTop = textOffset.dy;
    for (var i = 0; i < paragraphs.length; i++) {
      final table = _parseMarkdownTable(paragraphs[i]);
      if (table != null) {
        final height = _paintMarkdownTable(
          canvas,
          table,
          Offset(_cardHorizontalPadding, paragraphTop),
          textWidth,
          template,
        );
        paragraphTop += height;
        if (i < paragraphs.length - 1) {
          paragraphTop += _paragraphSpacing;
        }
        continue;
      }
      final textPainter = TextPainter(
        text: _shareTextSpan(
          paragraphs[i],
          TextStyle(
            fontSize: _bodyFontSize,
            height: 1.7,
            color: template.textColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textWidth);
      textPainter.paint(canvas, Offset(_cardHorizontalPadding, paragraphTop));
      paragraphTop += textPainter.height;
      if (i < paragraphs.length - 1) {
        paragraphTop += _paragraphSpacing;
      }
    }
    final footerTop = paragraphTop + _footerTopSpacing;
    final dividerPaint = Paint()
      ..color = template.accentColor.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(_cardHorizontalPadding, footerTop),
      Offset(_cardHorizontalPadding + textWidth, footerTop),
      dividerPaint,
    );
    final titlePainter = TextPainter(
      text: TextSpan(
        text: '《${widget.title}》',
        style: TextStyle(
          fontSize: _footerTitleFontSize,
          fontWeight: FontWeight.w600,
          color: template.textColor.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth);
    final authorPainter = TextPainter(
      text: TextSpan(
        text: widget.author,
        style: TextStyle(
          fontSize: _footerAuthorFontSize,
          color: template.textColor.withValues(alpha: 0.7),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth);
    final titleOffset = Offset(
      _cardHorizontalPadding,
      footerTop + _footerDividerSpacing,
    );
    titlePainter.paint(canvas, titleOffset);
    authorPainter.paint(
      canvas,
      Offset(
        _cardHorizontalPadding,
        titleOffset.dy + titlePainter.height + _footerTitleSpacing,
      ),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (cardWidth * pixelRatio).round(),
      (cardHeight * pixelRatio).round(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  List<String> _shareParagraphs(String text) {
    if (!widget.renderMarkdown) {
      return text
          .split(RegExp(r'\n\s*\n'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final paragraphs = <String>[];
    final buffer = <String>[];
    var inCodeBlock = false;
    void flush() {
      final value = buffer.join('\n').trim();
      if (value.isNotEmpty) paragraphs.add(value);
      buffer.clear();
    }

    final lines = text.split('\n');
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      final trimmed = line.trim();
      if (trimmed.startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        buffer.add(line);
        if (!inCodeBlock) flush();
        index += 1;
        continue;
      }
      if (!inCodeBlock &&
          index + 1 < lines.length &&
          _isMarkdownTableHeader(line, lines[index + 1])) {
        flush();
        final tableLines = <String>[line, lines[index + 1]];
        index += 2;
        while (index < lines.length && _isMarkdownTableRow(lines[index])) {
          tableLines.add(lines[index]);
          index += 1;
        }
        paragraphs.add(tableLines.join('\n'));
        continue;
      }
      if (!inCodeBlock && trimmed.isEmpty) {
        flush();
        index += 1;
        continue;
      }
      if (!inCodeBlock &&
          RegExp(r'^#{1,6}\s+').hasMatch(trimmed) &&
          buffer.isNotEmpty) {
        flush();
      }
      buffer.add(line);
      if (!inCodeBlock && RegExp(r'^#{1,6}\s+').hasMatch(trimmed)) {
        flush();
      }
      index += 1;
    }
    flush();
    return paragraphs;
  }

  bool _isMarkdownTableHeader(String header, String separator) {
    final headerCells = _splitMarkdownTableRow(header);
    final separatorCells = _splitMarkdownTableRow(separator);
    return headerCells.length >= 2 &&
        headerCells.length == separatorCells.length &&
        separatorCells.every(
          (cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell.trim()),
        );
  }

  bool _isMarkdownTableRow(String line) {
    return line.trim().contains('|') &&
        _splitMarkdownTableRow(line).length >= 2;
  }

  List<String> _splitMarkdownTableRow(String line) {
    var value = line.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|')) value = value.substring(0, value.length - 1);
    return value.split('|').map((cell) => cell.trim()).toList();
  }

  _MarkdownTable? _parseMarkdownTable(String text) {
    if (!widget.renderMarkdown) return null;
    final lines = text.trim().split('\n');
    if (lines.length < 2 || !_isMarkdownTableHeader(lines[0], lines[1])) {
      return null;
    }
    final header = _splitMarkdownTableRow(lines[0]);
    final rows = lines
        .skip(2)
        .where(_isMarkdownTableRow)
        .map(_splitMarkdownTableRow)
        .map(
          (row) => List<String>.generate(
            header.length,
            (index) => index < row.length ? row[index] : '',
          ),
        )
        .toList();
    return _MarkdownTable(header: header, rows: rows);
  }

  Widget _buildMarkdownTable(_MarkdownTable table, _ShareTemplate template) {
    final borderColor = template.accentColor.withValues(alpha: 0.7);
    Widget row(List<String> cells, {required bool header}) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final cell in cells)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(_tableCellPadding),
                  decoration: BoxDecoration(
                    color: header
                        ? template.accentColor.withValues(alpha: 0.12)
                        : null,
                    border: Border(
                      right: BorderSide(color: borderColor),
                      bottom: BorderSide(color: borderColor),
                    ),
                  ),
                  child: Text.rich(
                    _inlineMarkdownSpan(
                      cell,
                      TextStyle(
                        fontSize: _tableFontSize,
                        height: 1.4,
                        color: template.textColor,
                        fontWeight: header ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: borderColor),
          top: BorderSide(color: borderColor),
        ),
      ),
      child: Column(
        children: [
          row(table.header, header: true),
          for (final cells in table.rows) row(cells, header: false),
        ],
      ),
    );
  }

  double _measureMarkdownTableHeight(
    _MarkdownTable table,
    double maxWidth,
    TextStyle baseStyle,
  ) {
    final columnWidth = maxWidth / table.header.length;
    var height = 0.0;
    for (var rowIndex = 0; rowIndex <= table.rows.length; rowIndex++) {
      final cells = rowIndex == 0 ? table.header : table.rows[rowIndex - 1];
      var rowHeight = 0.0;
      for (final cell in cells) {
        final painter = TextPainter(
          text: _inlineMarkdownSpan(
            cell,
            baseStyle.copyWith(
              fontSize: _tableFontSize,
              height: 1.4,
              fontWeight: rowIndex == 0 ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: columnWidth - _tableCellPadding * 2);
        rowHeight = rowHeight < painter.height ? painter.height : rowHeight;
      }
      height += rowHeight + _tableCellPadding * 2;
    }
    return height;
  }

  double _paintMarkdownTable(
    Canvas canvas,
    _MarkdownTable table,
    Offset offset,
    double width,
    _ShareTemplate template,
  ) {
    final columnWidth = width / table.header.length;
    final borderPaint = Paint()
      ..color = template.accentColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final headerPaint = Paint()
      ..color = template.accentColor.withValues(alpha: 0.12);
    var top = offset.dy;
    for (var rowIndex = 0; rowIndex <= table.rows.length; rowIndex++) {
      final cells = rowIndex == 0 ? table.header : table.rows[rowIndex - 1];
      final painters = <TextPainter>[];
      var rowTextHeight = 0.0;
      for (final cell in cells) {
        final painter = TextPainter(
          text: _inlineMarkdownSpan(
            cell,
            TextStyle(
              fontSize: _tableFontSize,
              height: 1.4,
              color: template.textColor,
              fontWeight: rowIndex == 0 ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: columnWidth - _tableCellPadding * 2);
        painters.add(painter);
        rowTextHeight = rowTextHeight < painter.height
            ? painter.height
            : rowTextHeight;
      }
      final rowHeight = rowTextHeight + _tableCellPadding * 2;
      for (var column = 0; column < cells.length; column++) {
        final rect = Rect.fromLTWH(
          offset.dx + column * columnWidth,
          top,
          columnWidth,
          rowHeight,
        );
        if (rowIndex == 0) canvas.drawRect(rect, headerPaint);
        canvas.drawRect(rect, borderPaint);
        painters[column].paint(
          canvas,
          Offset(rect.left + _tableCellPadding, rect.top + _tableCellPadding),
        );
      }
      top += rowHeight;
    }
    return top - offset.dy;
  }

  TextSpan _shareTextSpan(String text, TextStyle baseStyle) {
    if (!widget.renderMarkdown) {
      return TextSpan(text: text, style: baseStyle);
    }
    final trimmed = text.trim();
    if (trimmed.startsWith('```') && trimmed.endsWith('```')) {
      final lines = trimmed.split('\n');
      final code = lines.length > 2
          ? lines.sublist(1, lines.length - 1).join('\n')
          : '';
      return TextSpan(
        text: code,
        style: baseStyle.copyWith(
          fontFamily: 'monospace',
          fontSize: _codeBlockFontSize,
          height: 1.55,
          backgroundColor: baseStyle.color?.withValues(alpha: 0.08),
        ),
      );
    }
    final heading = RegExp(r'^(#{1,6})\s+').firstMatch(trimmed);
    if (heading != null) {
      final level = heading.group(1)!.length;
      return _inlineMarkdownSpan(
        trimmed.substring(heading.end),
        baseStyle.copyWith(
          fontSize: level <= 2 ? 19 : 16,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    if (trimmed.startsWith('>')) {
      final quote = trimmed
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^\s*>\s?'), ''))
          .join('\n');
      return _inlineMarkdownSpan(
        '▌ $quote',
        baseStyle.copyWith(
          fontStyle: FontStyle.italic,
          color: baseStyle.color?.withValues(alpha: 0.72),
        ),
      );
    }
    final normalized = trimmed
        .split('\n')
        .map((line) {
          final bullet = RegExp(r'^\s*[-*+]\s+').firstMatch(line);
          if (bullet != null) return '• ${line.substring(bullet.end)}';
          return line;
        })
        .join('\n');
    return _inlineMarkdownSpan(normalized, baseStyle);
  }

  TextSpan _inlineMarkdownSpan(String text, TextStyle baseStyle) {
    final pattern = RegExp(
      r'(\*\*[^*]+\*\*|__[^_]+__|`[^`]+`|\*[^*]+\*|_[^_]+_|\[[^\]]+\]\([^)]+\))',
    );
    final children = <InlineSpan>[];
    var offset = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > offset) {
        children.add(
          TextSpan(text: text.substring(offset, match.start), style: baseStyle),
        );
      }
      final token = match.group(0)!;
      if ((token.startsWith('**') && token.endsWith('**')) ||
          (token.startsWith('__') && token.endsWith('__'))) {
        children.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: baseStyle.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else if (token.startsWith('`') && token.endsWith('`')) {
        children.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: baseStyle.copyWith(
              fontFamily: 'monospace',
              fontSize: (baseStyle.fontSize ?? _bodyFontSize) - 1,
              backgroundColor: baseStyle.color?.withValues(alpha: 0.08),
            ),
          ),
        );
      } else if (token.startsWith('[')) {
        final link = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$').firstMatch(token);
        children.add(
          TextSpan(
            text: link == null ? token : '${link.group(1)}\n${link.group(2)}',
            style: baseStyle.copyWith(
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      } else {
        children.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      offset = match.end;
    }
    if (offset < text.length) {
      children.add(TextSpan(text: text.substring(offset), style: baseStyle));
    }
    return TextSpan(style: baseStyle, children: children);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    _showToast(message);
  }

  void _showToast(String message) {
    _toastEntry?.remove();
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;
    final mediaQuery = MediaQuery.maybeOf(overlay.context);
    final topInset = mediaQuery?.padding.top ?? 0;
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: topInset + 16,
        left: 20,
        right: 20,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE61F1F1F),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _toastEntry = entry;
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_toastEntry == entry) {
        _toastEntry = null;
      }
      entry.remove();
    });
  }

  @override
  void dispose() {
    _toastEntry?.remove();
    _toastEntry = null;
    _pageController.dispose();
    super.dispose();
  }
}

class _ShareTemplate {
  const _ShareTemplate({
    required this.background,
    required this.textColor,
    required this.accentColor,
  });

  final Color background;
  final Color textColor;
  final Color accentColor;
}

class _MarkdownTable {
  const _MarkdownTable({required this.header, required this.rows});

  final List<String> header;
  final List<List<String>> rows;
}

class _ShareActionButton extends StatelessWidget {
  const _ShareActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? Colors.black87 : Colors.black26;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F4),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
