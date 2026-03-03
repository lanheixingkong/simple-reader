import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/library.dart';
import '../../services/library_store.dart';
import '../../services/pdf_page_ocr_service.dart';
import '../../services/pdf_page_text_extractor.dart';
import '../../services/pdf_text_api_store.dart';
import '../../services/pdf_text_page_cache_store.dart';
import '../../services/settings_store.dart';
import 'ai_chat_screen.dart';
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
  static const _modeKeyPrefix = 'pdf_reader_mode_';

  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;
  final _pdfApiStore = PdfTextApiStore.instance;
  final _textCacheStore = PdfTextPageCacheStore.instance;
  final _textExtractor = const PdfPageTextExtractor();
  final _ocrService = PdfPageOcrService();

  ReaderSettings? _settings;
  PdfTextApiSettings? _pdfApiSettings;
  PdfController? _controller;
  Timer? _saveTimer;
  final ValueNotifier<bool> _showChrome = ValueNotifier<bool>(false);

  final Map<int, _PageTextResult> _pageTextCache = <int, _PageTextResult>{};
  final Map<int, Future<_PageTextResult>> _inFlightTextLoads =
      <int, Future<_PageTextResult>>{};
  Timer? _cacheSaveTimer;

  bool _textMode = false;
  bool _switchingMode = false;
  bool _textModeLoading = false;
  int _textModePage = 1;
  int _totalPages = 1;
  String? _textModeError;
  _PageTextResult? _textModeResult;
  Future<void> _prefetchQueue = Future<void>.value();
  String _selectedText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    unawaited(_persistTextCache());
    _controller?.dispose();
    _saveTimer?.cancel();
    _cacheSaveTimer?.cancel();
    _showChrome.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    final apiSettings = await _pdfApiStore.load();
    final prefs = await SharedPreferences.getInstance();
    final restoreTextMode =
        prefs.getBool('$_modeKeyPrefix${widget.book.id}') ?? false;
    final initialPage = (widget.book.lastPage ?? 1).clamp(1, 999999);
    final controller = PdfController(
      document: PdfDocument.openFile(widget.book.path),
      initialPage: initialPage,
    );
    _settings = settings;
    _pdfApiSettings = apiSettings;
    _controller = controller;
    _textModePage = initialPage;
    await _loadPersistedTextCache(apiSettings);
    _textMode = restoreTextMode;
    unawaited(_refreshTotalPages());
    if (restoreTextMode) {
      unawaited(_loadTextModePage(pageNumber: initialPage));
      _enqueuePrefetch(centerPage: initialPage);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshTotalPages() async {
    final total = await _resolveTotalPages();
    if (!mounted) return;
    setState(() {
      _totalPages = total;
      if (_textModePage > total) {
        _textModePage = total;
      }
    });
  }

  Future<void> _saveProgress() async {
    final page = _textMode ? _textModePage : _controller?.pageListenable.value;
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
          onPressed: _switchingMode ? null : _toggleTextMode,
          icon: _switchingMode
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _textMode
                      ? Icons.picture_as_pdf_outlined
                      : Icons.text_snippet_outlined,
                ),
          tooltip: _textMode ? '切换到PDF页面' : '切换到文本页面',
        ),
        IconButton(
          onPressed: _shareCurrentPage,
          icon: const Icon(Icons.ios_share),
          tooltip: '分享',
        ),
      ],
      bottomActions: [
        IconButton(
          onPressed: () => _openAiChat(),
          icon: const Icon(Icons.chat_bubble_outline),
          tooltip: 'AI问答',
        ),
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
            : _buildReaderBody(controller),
      ),
    );
  }

  Widget _buildReaderBody(PdfController controller) {
    if (!_textMode) {
      return PdfView(
        controller: controller,
        physics: const NeverScrollableScrollPhysics(),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: _buildTextModeContent(),
    );
  }

  Widget _buildTextModeContent() {
    if (_textModeLoading && _textModeResult == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_textModeError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _textModeError!,
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => _loadTextModePage(
                pageNumber: _textModePage,
                forceRefresh: true,
              ),
              child: const Text('重试本页'),
            ),
          ],
        ),
      );
    }

    final text = _textModeResult?.text ?? '';
    if (text.isEmpty) {
      return const Center(child: Text('无文本内容'));
    }

    return SingleChildScrollView(
      key: ValueKey<int>(_textModePage),
      child: SelectionArea(
        onSelectionChanged: (content) {
          _selectedText = content?.plainText.trim() ?? '';
        },
        contextMenuBuilder: (context, selectableRegionState) {
          final items = List<ContextMenuButtonItem>.from(
            selectableRegionState.contextMenuButtonItems,
          );
          final localizedItems = items.map(_localizedMenuItem).toList();
          localizedItems.add(
            ContextMenuButtonItem(
              label: 'AI问答',
              onPressed: () {
                final selected = _selectedText;
                selectableRegionState.hideToolbar();
                _openAiChat(quote: selected);
              },
            ),
          );
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: selectableRegionState.contextMenuAnchors,
            buttonItems: localizedItems,
          );
        },
        child: Text(
          text,
          style: TextStyle(
            fontSize: (_settings?.fontSize ?? 18) * 0.95,
            height: 1.65,
          ),
        ),
      ),
    );
  }

  void _toggleChrome() {
    _showChrome.value = !_showChrome.value;
  }

  void _previousPage() {
    if (_textMode) {
      _changeTextModePage(-1);
      return;
    }
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
    if (_textMode) {
      _changeTextModePage(1);
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    final current = controller.pageListenable.value;
    final total = controller.pagesCount ?? _totalPages;
    if (current >= total) return;
    controller.nextPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _changeTextModePage(int delta) async {
    final target = (_textModePage + delta).clamp(1, _totalPages);
    if (target == _textModePage) return;
    setState(() {
      _textModePage = target;
      _textModeResult = null;
      _textModeError = null;
    });
    await _loadTextModePage(pageNumber: target);
    _ensurePrefetchAround(target);
  }

  Future<void> _toggleTextMode() async {
    final controller = _controller;
    if (controller == null || _switchingMode) return;

    if (_textMode) {
      await _exitTextMode();
      return;
    }

    final currentPage = controller.pageListenable.value;
    setState(() {
      _textMode = true;
      _textModePage = currentPage;
      _textModeResult = null;
      _textModeError = null;
    });
    unawaited(_persistReaderMode(true));
    await _loadTextModePage(pageNumber: currentPage);
    _ensurePrefetchAround(currentPage);
  }

  Future<void> _exitTextMode() async {
    setState(() => _switchingMode = true);
    try {
      await _recreateControllerAtPage(_textModePage);
      if (!mounted) return;
      setState(() {
        _textMode = false;
        _textModeError = null;
      });
      unawaited(_persistReaderMode(false));
    } finally {
      if (mounted) {
        setState(() => _switchingMode = false);
      }
    }
  }

  Future<void> _recreateControllerAtPage(int pageNumber) async {
    final oldController = _controller;
    final nextController = PdfController(
      document: PdfDocument.openFile(widget.book.path),
      initialPage: pageNumber,
    );
    _controller = nextController;
    oldController?.dispose();
    await _refreshTotalPages();
  }

  Future<void> _loadTextModePage({
    required int pageNumber,
    bool forceRefresh = false,
  }) async {
    setState(() {
      _textModeLoading = true;
      _textModeError = null;
    });
    try {
      final result = await _loadPageText(
        pageNumber: pageNumber,
        forceRefresh: forceRefresh,
      );
      if (!mounted || !_textMode || _textModePage != pageNumber) return;
      setState(() {
        _textModeResult = result;
        _textModeError = null;
      });
    } catch (err) {
      if (!mounted || !_textMode || _textModePage != pageNumber) return;
      final message = err is PdfOcrException ? err.userMessage() : '转文本失败：$err';
      setState(() {
        _textModeError = message;
      });
    } finally {
      if (mounted && _textMode && _textModePage == pageNumber) {
        setState(() => _textModeLoading = false);
      }
    }
  }

  void _enqueuePrefetch({required int centerPage}) {
    _prefetchQueue = _prefetchQueue.then((_) => _prefetchNearby(centerPage));
  }

  void _ensurePrefetchAround(int centerPage) {
    _enqueuePrefetch(centerPage: centerPage);
  }

  Future<void> _prefetchNearby(int centerPage) async {
    if (!_textMode) return;
    final radius = _prefetchRadius();
    final total = _totalPages;
    final start = (centerPage - radius).clamp(1, total);
    final end = (centerPage + radius).clamp(1, total);
    for (var page = start; page <= end; page++) {
      if (!_textMode) return;
      if (_pageTextCache.containsKey(page)) continue;
      try {
        await _loadPageText(pageNumber: page);
      } catch (_) {
        // Prefetch errors are ignored; current page load handles user feedback.
      }
    }
  }

  int _prefetchRadius() {
    return (_pdfApiSettings?.prefetchPages ?? 10).clamp(0, 50);
  }

  Future<void> _shareCurrentPage() async {
    final controller = _controller;
    if (controller == null) return;
    final pageNumber = _textMode
        ? _textModePage
        : controller.pageListenable.value;
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
            _inFlightTextLoads.clear();
            await _loadPersistedTextCache(updated);
            if (mounted) {
              setState(() => _pdfApiSettings = updated);
            }
            if (_textMode) {
              await _loadTextModePage(
                pageNumber: _textModePage,
                forceRefresh: true,
              );
              _ensurePrefetchAround(_textModePage);
            }
          },
        ),
      ),
    );
  }

  Future<String> _testPdfApiSettings(PdfTextApiSettings settings) {
    return _ocrService.testSettings(settings: settings);
  }

  Future<void> _loadPersistedTextCache(PdfTextApiSettings settings) async {
    final cached = await _textCacheStore.load(
      bookId: widget.book.id,
      settings: settings,
    );
    _pageTextCache
      ..clear()
      ..addEntries(
        cached.entries.map(
          (entry) => MapEntry(
            entry.key,
            _PageTextResult(text: entry.value.text, source: entry.value.source),
          ),
        ),
      );
  }

  void _schedulePersistTextCache() {
    _cacheSaveTimer?.cancel();
    _cacheSaveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_persistTextCache());
    });
  }

  Future<void> _persistTextCache() async {
    final settings = _pdfApiSettings;
    if (settings == null) return;
    final pages = <int, PdfTextCachedPage>{
      for (final entry in _pageTextCache.entries)
        entry.key: PdfTextCachedPage(
          text: entry.value.text,
          source: entry.value.source,
        ),
    };
    await _textCacheStore.saveAll(
      bookId: widget.book.id,
      settings: settings,
      pages: pages,
    );
  }

  Future<void> _persistReaderMode(bool textMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_modeKeyPrefix${widget.book.id}', textMode);
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
  }) {
    if (!forceRefresh) {
      final cached = _pageTextCache[pageNumber];
      if (cached != null) return Future<_PageTextResult>.value(cached);
      final loading = _inFlightTextLoads[pageNumber];
      if (loading != null) return loading;
    }

    final future = _loadPageTextInternal(
      pageNumber: pageNumber,
      forceRefresh: forceRefresh,
    );
    _inFlightTextLoads[pageNumber] = future;
    return future.whenComplete(() => _inFlightTextLoads.remove(pageNumber));
  }

  Future<_PageTextResult> _loadPageTextInternal({
    required int pageNumber,
    required bool forceRefresh,
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
      final result = _PageTextResult(text: localText, source: '文本层');
      _pageTextCache[pageNumber] = result;
      _schedulePersistTextCache();
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
      text: text,
      source: settings.providerLabel(),
    );
    _pageTextCache[pageNumber] = result;
    _schedulePersistTextCache();
    return result;
  }

  Future<void> _openAiChat({String? quote}) async {
    final value = quote?.trim();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiChatScreen(
          book: widget.book,
          initialQuote: value != null && value.isNotEmpty ? value : null,
        ),
      ),
    );
  }

  ContextMenuButtonItem _localizedMenuItem(ContextMenuButtonItem item) {
    final label = switch (item.type) {
      ContextMenuButtonType.copy => '复制',
      ContextMenuButtonType.selectAll => '全选',
      ContextMenuButtonType.cut => '剪切',
      ContextMenuButtonType.paste => '粘贴',
      _ => item.label,
    };
    if (label == item.label) return item;
    return ContextMenuButtonItem(
      type: item.type,
      label: label,
      onPressed: item.onPressed,
    );
  }
}

class _PageTextResult {
  const _PageTextResult({required this.text, required this.source});

  final String text;
  final String source;
}
