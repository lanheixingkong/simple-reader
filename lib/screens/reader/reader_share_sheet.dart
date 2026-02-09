import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
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
  });

  final String title;
  final String author;
  final String text;
  final String sourceLabel;

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

  bool _busy = false;
  int _templateIndex = 0;
  int _currentPage = 0;
  Size? _lastLayoutSize;
  List<String> _pages = const [];
  final PageController _pageController = PageController();

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

  Widget _buildPreview(Size size, double cardWidth, _ShareTemplate template,
      double maxCardHeight) {
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
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
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

  Widget _buildShareCard(String text, _ShareTemplate template, double cardWidth,
      double maxCardHeight) {
    final contentHeight = _cardHeightForText(
      text,
      cardWidth,
      template,
      maxCardHeight,
    );
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaleFactor: 1.0),
      child: Container(
        width: cardWidth,
        height: contentHeight,
        decoration: BoxDecoration(
          color: template.background,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
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
            Text(
              text,
              style: TextStyle(
                fontSize: 16,
                height: 1.7,
                color: template.textColor,
              ),
            ),
            const SizedBox(height: _footerTopSpacing),
            Container(
              height: 1,
              color: template.accentColor.withOpacity(0.6),
            ),
            const SizedBox(height: _footerDividerSpacing),
            Text(
              '《${widget.title}》',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: template.textColor.withOpacity(0.85),
              ),
            ),
            const SizedBox(height: _footerTitleSpacing),
            Text(
              widget.author,
              style: TextStyle(
                fontSize: 13,
                color: template.textColor.withOpacity(0.7),
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
    await Share.shareXFiles(
      files.map((file) => XFile(file.path)).toList(),
      text: '${widget.title} · ${widget.author}',
    );
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
        final file = File(
          p.join(
            dir.path,
            'reader-share-${DateTime.now().millisecondsSinceEpoch}-$i.png',
          ),
        );
        await file.writeAsBytes(bytesList[i]);
        files.add(file);
      }
      return files;
    } catch (_) {
      return [];
    }
  }

  void _ensurePagedText(
      Size size, double cardWidth, double maxCardHeight) {
    if (_lastLayoutSize == size && _pages.isNotEmpty) return;
    _lastLayoutSize = size;
    final pages = _paginateText(
      widget.text.trim(),
      cardWidth,
      maxCardHeight,
    );
    _pages = pages.isEmpty ? [''] : pages;
    _currentPage = 0;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  List<String> _paginateText(
      String text, double cardWidth, double maxCardHeight) {
    if (text.isEmpty) return [''];
    const textStyle = TextStyle(fontSize: 16, height: 1.7);
    const titleStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    const authorStyle = TextStyle(fontSize: 13);
    final textWidth = cardWidth - _cardHorizontalPadding * 2;
    final footerHeight = _measureFooterHeight(
      textWidth,
      titleStyle,
      authorStyle,
    );
    final maxTextHeight = (maxCardHeight -
            _cardVerticalPadding * 2 -
            footerHeight)
        .clamp(80.0, maxCardHeight);
    final pages = <String>[];
    var start = 0;
    while (start < text.length) {
      var low = start + 1;
      var high = text.length;
      var best = low;
      while (low <= high) {
        final mid = (low + high) >> 1;
        final candidate = text.substring(start, mid);
        final height =
            _measureTextHeight(candidate, textWidth, textStyle);
        if (height <= maxTextHeight) {
          best = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
      final pageText = text.substring(start, best).trim();
      if (pageText.isNotEmpty) {
        pages.add(pageText);
      }
      start = best;
    }
    return pages;
  }

  double _measureTextHeight(
      String text, double maxWidth, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  double _measureFooterHeight(
      double maxWidth, TextStyle titleStyle, TextStyle authorStyle) {
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

  double _cardHeightForText(String text, double cardWidth,
      _ShareTemplate template, double maxCardHeight) {
    final textWidth = cardWidth - _cardHorizontalPadding * 2;
    final textHeight = _measureTextHeight(
      text,
      textWidth,
      TextStyle(fontSize: 16, height: 1.7, color: template.textColor),
    );
    final footerHeight = _measureFooterHeight(
      textWidth,
      TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: template.textColor.withOpacity(0.85)),
      TextStyle(fontSize: 13, color: template.textColor.withOpacity(0.7)),
    );
    final targetHeight = _cardVerticalPadding * 2 + textHeight + footerHeight;
    return targetHeight.clamp(260.0, maxCardHeight);
  }

  Future<Uint8List?> _renderShareImage(
      String text, _ShareTemplate template, double pixelRatio) async {
    final size = MediaQuery.of(context).size;
    final cardWidth = (size.width - 48).clamp(240.0, 420.0);
    final maxCardHeight = _maxImageHeightPx / pixelRatio;
    final cardHeight =
        _cardHeightForText(text, cardWidth, template, maxCardHeight);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    final rect = Rect.fromLTWH(0, 0, cardWidth, cardHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    final paint = Paint()..color = template.background;
    canvas.drawRRect(rrect, paint);
    final textWidth = cardWidth - _cardHorizontalPadding * 2;
    final textOffset =
        Offset(_cardHorizontalPadding, _cardVerticalPadding);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 16,
          height: 1.7,
          color: template.textColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth);
    textPainter.paint(canvas, textOffset);
    final footerTop = textOffset.dy + textPainter.height + _footerTopSpacing;
    final dividerPaint = Paint()
      ..color = template.accentColor.withOpacity(0.6)
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
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: template.textColor.withOpacity(0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth);
    final authorPainter = TextPainter(
      text: TextSpan(
        text: widget.author,
        style: TextStyle(
          fontSize: 13,
          color: template.textColor.withOpacity(0.7),
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
