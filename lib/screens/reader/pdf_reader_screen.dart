import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/library.dart';
import '../../services/library_store.dart';
import '../../services/pdf_page_ocr_service.dart';
import '../../services/pdf_page_text_extractor.dart';
import '../../services/pdf_text_api_store.dart';
import '../../services/settings_store.dart';
import 'pdf_text_api_settings_sheet.dart';
import 'reader_layout.dart';
import 'reader_settings_sheet.dart';
import 'reader_tap_zones.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;
  final _pdfApiStore = PdfTextApiStore.instance;
  final _textExtractor = const PdfPageTextExtractor();
  final _ocrService = PdfPageOcrService();

  ReaderSettings? _settings;
  PdfTextApiSettings? _pdfApiSettings;
  PdfController? _controller;
  Timer? _saveTimer;
  final ValueNotifier<bool> _showChrome = ValueNotifier<bool>(false);
  final Map<int, _PageTextResult> _pageTextCache = <int, _PageTextResult>{};
  bool _converting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    _controller?.dispose();
    _saveTimer?.cancel();
    _showChrome.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    final apiSettings = await _pdfApiStore.load();
    _settings = settings;
    _pdfApiSettings = apiSettings;
    _controller = PdfController(
      document: PdfDocument.openFile(widget.book.path),
      initialPage: (widget.book.lastPage ?? 1).clamp(1, 999999),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveProgress() async {
    final page = _controller?.pageListenable.value;
    if (page != null) {
      await _store.updateBookProgress(widget.book.id, lastPage: page);
    }
  }

  void _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => ReaderSettingsSheet(
        settings: settings,
        onChanged: (updated) {
          _applySettings(updated);
        },
      ),
    );
  }

  Future<void> _applySettings(ReaderSettings updated) async {
    _scheduleSave(updated);
    setState(() => _settings = updated);
  }

  void _scheduleSave(ReaderSettings updated) {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 300),
      () => _settingsStore.save(updated),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = _controller;
    return ReaderLayout(
      book: widget.book,
      settings: settings,
      showAppBarListenable: _showChrome,
      actions: [
        IconButton(
          onPressed: _convertCurrentPageToText,
          icon: _converting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.text_snippet_outlined),
          tooltip: '转为文本',
        ),
        IconButton(
          onPressed: _shareCurrentPage,
          icon: const Icon(Icons.ios_share),
          tooltip: '分享',
        ),
      ],
      bottomActions: [
        IconButton(
          onPressed: _openPdfApiSettings,
          icon: const Icon(Icons.smart_toy_outlined),
          tooltip: 'PDF识别接口',
        ),
        IconButton(
          onPressed: _openSettings,
          icon: const Icon(Icons.text_fields),
          tooltip: '阅读设置',
        ),
      ],
      child: ReaderTapZones(
        onTapLeft: _previousPage,
        onTapRight: _nextPage,
        onTapCenter: _toggleChrome,
        child: controller == null
            ? const Center(child: CircularProgressIndicator())
            : PdfView(
                controller: controller,
                physics: const NeverScrollableScrollPhysics(),
              ),
      ),
    );
  }

  void _toggleChrome() {
    _showChrome.value = !_showChrome.value;
  }

  void _previousPage() {
    final controller = _controller;
    if (controller == null) return;
    final current = controller.pageListenable.value;
    if (current <= 1) return;
    controller.previousPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _nextPage() {
    final controller = _controller;
    if (controller == null) return;
    final current = controller.pageListenable.value;
    final total = controller.pagesCount ?? 0;
    if (current >= total) return;
    controller.nextPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _shareCurrentPage() async {
    final controller = _controller;
    if (controller == null) return;
    final pageNumber = controller.pageListenable.value;
    try {
      final document = await controller.document;
      final page = await document.getPage(pageNumber);
      final targetWidth = 1080.0;
      final targetHeight = page.height / page.width * targetWidth;
      final image = await page.render(
        width: targetWidth,
        height: targetHeight,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
        quality: 100,
      );
      await page.close();
      if (image == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(
          dir.path,
          'reader-share-pdf-${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      );
      await file.writeAsBytes(image.bytes);
      await Share.shareXFiles([XFile(file.path)], text: widget.book.title);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('生成分享图片失败')));
    }
  }

  Future<void> _openPdfApiSettings() async {
    final current = _pdfApiSettings ?? await _pdfApiStore.load();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: PdfTextApiSettingsSheet(
          initial: current,
          onTest: _testPdfApiSettings,
          onSave: (updated) async {
            await _pdfApiStore.save(updated);
            _pageTextCache.clear();
            if (mounted) {
              setState(() => _pdfApiSettings = updated);
            }
          },
        ),
      ),
    );
  }

  Future<String> _testPdfApiSettings(PdfTextApiSettings settings) {
    return _ocrService.testSettings(settings: settings);
  }

  Future<void> _convertCurrentPageToText() async {
    final controller = _controller;
    if (controller == null || _converting) return;
    final pageNumber = controller.pageListenable.value;
    setState(() => _converting = true);
    try {
      final totalPages = await _resolveTotalPages();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _PdfTextModeSheet(
          initialPage: pageNumber,
          totalPages: totalPages,
          loadPage: (page, forceRefresh) =>
              _loadPageText(pageNumber: page, forceRefresh: forceRefresh),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      final message = err is PdfOcrException ? err.userMessage() : '转文本失败：$err';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _converting = false);
      }
    }
  }

  Future<List<int>?> _renderPageAsPngBytes(int pageNumber) async {
    final controller = _controller;
    if (controller == null) return null;
    final document = await controller.document;
    final page = await document.getPage(pageNumber);
    try {
      final targetWidth = 1400.0;
      final targetHeight = page.height / page.width * targetWidth;
      final image = await page.render(
        width: targetWidth,
        height: targetHeight,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
        quality: 100,
      );
      return image?.bytes;
    } finally {
      await page.close();
    }
  }

  Future<int> _resolveTotalPages() async {
    final controller = _controller;
    if (controller == null) return 1;
    final count = controller.pagesCount;
    if (count != null && count > 0) return count;
    final document = await controller.document;
    return document.pagesCount;
  }

  Future<_PageTextResult> _loadPageText({
    required int pageNumber,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _pageTextCache[pageNumber];
      if (cached != null) return cached;
    }

    final localText = await _textExtractor.extractTextLayer(
      pdfPath: widget.book.path,
      pageNumber: pageNumber,
    );
    if (localText.length >= 10) {
      final result = _PageTextResult(
        pageNumber: pageNumber,
        text: localText,
        source: '文本层',
      );
      _pageTextCache[pageNumber] = result;
      return result;
    }

    final settings = _pdfApiSettings ?? await _pdfApiStore.load();
    _pdfApiSettings = settings;
    final imageBytes = await _renderPageAsPngBytes(pageNumber);
    if (imageBytes == null || imageBytes.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: '页面渲染失败',
        provider: settings.provider,
      );
    }
    final recognized = await _ocrService.recognizeText(
      imageBytes: imageBytes,
      settings: settings,
    );
    final text = recognized.trim();
    if (text.isEmpty) {
      throw PdfOcrException(
        level: PdfOcrErrorLevel.response,
        message: '接口未返回文本',
        provider: settings.provider,
      );
    }
    final result = _PageTextResult(
      pageNumber: pageNumber,
      text: text,
      source: settings.providerLabel(),
    );
    _pageTextCache[pageNumber] = result;
    return result;
  }
}

class _PdfTextModeSheet extends StatefulWidget {
  const _PdfTextModeSheet({
    required this.initialPage,
    required this.totalPages,
    required this.loadPage,
  });

  final int initialPage;
  final int totalPages;
  final Future<_PageTextResult> Function(int pageNumber, bool forceRefresh)
  loadPage;

  @override
  State<_PdfTextModeSheet> createState() => _PdfTextModeSheetState();
}

class _PdfTextModeSheetState extends State<_PdfTextModeSheet> {
  late int _currentPage;
  _PageTextResult? _result;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _fetchPage(_currentPage);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '文本页模式 $_currentPage/${widget.totalPages}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: 4),
                Text(
                  '来源：${_result!.source}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(child: _buildBody()),
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    onPressed: _loading || _currentPage <= 1
                        ? null
                        : () => _fetchPage(_currentPage - 1),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '上一页',
                  ),
                  IconButton(
                    onPressed: _loading || _currentPage >= widget.totalPages
                        ? null
                        : () => _fetchPage(_currentPage + 1),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '下一页',
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => _fetchPage(_currentPage, true),
                    child: const Text('重试'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SingleChildScrollView(
        child: SelectableText(
          _error!,
          style: const TextStyle(fontSize: 14, color: Colors.redAccent),
        ),
      );
    }
    final text = _result?.text ?? '';
    if (text.isEmpty) {
      return const Center(child: Text('无文本'));
    }
    return SingleChildScrollView(
      child: SelectableText(
        text,
        style: const TextStyle(height: 1.5, fontSize: 15),
      ),
    );
  }

  Future<void> _fetchPage(int page, [bool forceRefresh = false]) async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPage = page;
    });
    try {
      final result = await widget.loadPage(page, forceRefresh);
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = null;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      final msg = err is PdfOcrException ? err.userMessage() : '转文本失败：$err';
      setState(() {
        _error = msg;
        _loading = false;
      });
    }
  }
}

class _PageTextResult {
  const _PageTextResult({
    required this.pageNumber,
    required this.text,
    required this.source,
  });

  final int pageNumber;
  final String text;
  final String source;
}
