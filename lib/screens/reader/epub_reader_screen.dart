import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:epubx/epubx.dart' show EpubBookRef, EpubChapterRef, EpubReader;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/library.dart';
import '../../services/ai_chat_api_store.dart';
import '../../services/book_translation_cache_store.dart';
import '../../services/book_translation_service.dart';
import '../../services/library_store.dart';
import '../../services/persistent_kv_store.dart';
import '../../services/settings_store.dart';
import 'reader_layout.dart';
import 'ai_chat_screen.dart';
import 'reader_share_sheet.dart';
import 'reader_settings_sheet.dart';
import 'reader_selection_auto_scroll.dart';
import 'reader_tap_zones.dart';

class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen>
    with WidgetsBindingObserver {
  static const _translationModeKeyPrefix = 'epub_translation_mode_';

  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;
  final _aiApiStore = AiChatApiStore.instance;
  final _translationCacheStore = BookTranslationCacheStore.instance;
  final _translationService = BookTranslationService();

  ReaderSettings? _settings;
  AiChatApiSettings? _translationSettings;
  EpubBookRef? _bookRef;
  List<_EpubChapterEntry> _chapters = [];
  PageController? _pageController;
  final Map<int, ScrollController> _scrollControllers = {};
  int _currentChapter = 0;
  final Map<int, double> _chapterOffsets = {};
  final Map<int, double> _chapterProgress = {};
  final Set<int> _restoredChapters = {};
  final Map<String, String> _imageCache = {};
  final Map<String, Future<String>> _chapterHtmlCache = {};
  final Map<String, List<_HtmlBlock>> _chapterBlocksCache = {};
  final Map<int, List<GlobalKey>> _blockKeys = {};
  final Map<int, GlobalKey> _scrollKeys = {};
  final Map<String, String> _translations = {};
  final Set<int> _translatingChapters = <int>{};
  final Map<int, Future<void>> _inFlightTranslations = <int, Future<void>>{};
  String _selectedText = '';
  final ValueNotifier<bool> _selectionActive = ValueNotifier<bool>(false);
  Timer? _saveTimer;
  Timer? _progressSaveTimer;
  Timer? _translationSaveTimer;
  Future<void> _translationQueue = Future<void>.value();
  bool _progressDirty = false;
  bool _savingProgress = false;
  bool _translationEnabled = false;
  final ValueNotifier<bool> _showChrome = ValueNotifier<bool>(false);
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    _pageController?.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _saveTimer?.cancel();
    _progressSaveTimer?.cancel();
    _translationSaveTimer?.cancel();
    unawaited(_persistTranslations());
    _showChrome.dispose();
    _selectionActive.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveProgress();
    }
  }

  Future<void> _load() async {
    try {
      final settings = await _settingsStore.load();
      final translationSettings = await _loadTranslationSettings();
      final translationEnabled =
          await PersistentKvStore.instance.getBool(
            '$_translationModeKeyPrefix${widget.book.id}',
          ) ??
          false;
      final bytes = await File(widget.book.path).readAsBytes();
      final bookRef = await EpubReader.openBook(bytes);
      final chapterRefs = await bookRef.getChapters();
      final chapters = await _buildChapters(bookRef, chapterRefs);
      final initialPage = widget.book.lastPage ?? 0;
      final safeInitial = chapters.isEmpty
          ? 0
          : initialPage.clamp(0, chapters.length - 1);
      final rawOffset = widget.book.lastOffset ?? 0.0;
      final initialOffset = rawOffset < 0 ? 0.0 : rawOffset;
      final rawProgress = widget.book.lastProgress;
      if (rawProgress != null && rawProgress >= 0 && rawProgress <= 1) {
        _chapterProgress[safeInitial] = rawProgress;
      }
      _pageController?.dispose();
      _pageController = PageController(initialPage: safeInitial);
      _settings = settings;
      _translationSettings = translationSettings;
      _bookRef = bookRef;
      _chapters = chapters;
      _currentChapter = safeInitial;
      _chapterOffsets[safeInitial] = initialOffset;
      _translations
        ..clear()
        ..addAll(
          await _translationCacheStore.load(
            bookId: widget.book.id,
            settings: translationSettings,
          ),
        );
      _translationEnabled = translationEnabled;
      _loadError = null;
      if (mounted) {
        setState(() {});
      }
      _warmChapter(safeInitial);
      if (_translationEnabled) {
        _enqueueTranslationAround(centerChapter: safeInitial);
      }
    } catch (e) {
      _loadError = '无法打开这本 EPUB：$e';
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _saveProgress() async {
    final offset = _currentOffset();
    final progress = _currentProgress();
    await _store.updateBookProgress(
      widget.book.id,
      lastPage: _currentChapter,
      lastOffset: offset,
      lastProgress: progress,
    );
  }

  void _scheduleProgressSave() {
    _progressDirty = true;
    if (_progressSaveTimer != null) return;
    _progressSaveTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _flushProgressSave(),
    );
  }

  Future<void> _flushProgressSave() async {
    if (_savingProgress) return;
    if (!_progressDirty) {
      _progressSaveTimer?.cancel();
      _progressSaveTimer = null;
      return;
    }
    _progressDirty = false;
    _savingProgress = true;
    try {
      await _saveProgress();
    } finally {
      _savingProgress = false;
    }
  }

  double _currentOffset() {
    final controller = _scrollControllers[_currentChapter];
    if (controller != null && controller.hasClients) {
      return controller.offset;
    }
    return _chapterOffsets[_currentChapter] ?? 0.0;
  }

  double _currentProgress() {
    final controller = _scrollControllers[_currentChapter];
    if (controller != null && controller.hasClients) {
      final max = controller.position.maxScrollExtent;
      if (max > 0) {
        return (controller.offset / max).clamp(0.0, 1.0);
      }
    }
    return _chapterProgress[_currentChapter] ?? 0.0;
  }

  ScrollController _controllerForChapter(int index) {
    return _scrollControllers.putIfAbsent(index, () {
      final initialOffset = _chapterOffsets[index] ?? 0.0;
      final controller = ScrollController(initialScrollOffset: initialOffset);
      controller.addListener(() {
        _chapterOffsets[index] = controller.offset;
        final max = controller.hasClients
            ? controller.position.maxScrollExtent
            : 0.0;
        if (max > 0) {
          _chapterProgress[index] = (controller.offset / max).clamp(0.0, 1.0);
        }
        if (index == _currentChapter) {
          _scheduleProgressSave();
        }
      });
      return controller;
    });
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
    setState(() {
      _settings = updated;
      _chapterHtmlCache.clear();
      _chapterBlocksCache.clear();
      _blockKeys.clear();
      _scrollKeys.clear();
    });
    _warmChapter(_currentChapter);
  }

  void _scheduleSave(ReaderSettings updated) {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 300),
      () => _settingsStore.save(updated),
    );
  }

  void _openToc() {
    if (_chapters.isEmpty) return;
    showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          itemCount: _chapters.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(_chapters[index].title),
            onTap: () => Navigator.pop(context, index),
          ),
        ),
      ),
    ).then((index) {
      if (index == null) return;
      setState(() => _currentChapter = index);
      _pageController?.jumpToPage(index);
      if (_translationEnabled) {
        _enqueueTranslationAround(centerChapter: index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loadError = _loadError;
    if (loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 36),
                const SizedBox(height: 12),
                Text(loadError, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _loadError = null;
                    });
                    _load();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final settings = _settings;
    final bookRef = _bookRef;
    if (settings == null || bookRef == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        unawaited(_saveProgress());
      },
      child: ReaderLayout(
        book: widget.book,
        settings: settings,
        showAppBarListenable: _showChrome,
        actions: [
          IconButton(
            onPressed: _shareCurrentScreen,
            icon: const Icon(Icons.ios_share),
            tooltip: '分享',
          ),
        ],
        bottomActions: [
          IconButton(
            onPressed: _openToc,
            icon: const Icon(Icons.list),
            tooltip: '目录',
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.text_fields),
            tooltip: '字体/背景',
          ),
          IconButton(
            onPressed: () => _openAiChat(),
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'AI问答',
          ),
          IconButton(
            onPressed: _isCurrentChapterTranslating
                ? null
                : _translateCurrentChapter,
            icon: _isCurrentChapterTranslating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _translationEnabled ? Icons.translate : Icons.g_translate,
                  ),
            tooltip: _translationEnabled ? '自动翻译已开启' : '开启自动翻译',
          ),
        ],
        child: ReaderTapZones(
          onTapLeft: _previousChapter,
          onTapRight: _nextChapter,
          onTapCenter: _toggleChrome,
          child: _chapters.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    _currentChapter = index;
                    _chapterOffsets.putIfAbsent(index, () => 0.0);
                    _chapterProgress.putIfAbsent(index, () => 0.0);
                    _scheduleProgressSave();
                    _warmChapter(index);
                    if (_translationEnabled) {
                      _enqueueTranslationAround(centerChapter: index);
                    }
                  },
                  itemCount: _chapters.length,
                  itemBuilder: (context, index) =>
                      _buildChapterPage(context, bookRef, settings, index),
                ),
        ),
      ),
    );
  }

  void _toggleChrome() {
    _showChrome.value = !_showChrome.value;
  }

  void _previousChapter() {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    if (_currentChapter <= 0) return;
    controller.previousPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _nextChapter() {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    if (_currentChapter >= _chapters.length - 1) return;
    controller.nextPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Widget _buildChapterPage(
    BuildContext context,
    EpubBookRef bookRef,
    ReaderSettings settings,
    int index,
  ) {
    final chapter = _chapters[index];
    final future = _chapterHtmlCache.putIfAbsent(
      chapter.cacheKey,
      () => _buildChapterHtml(bookRef, settings, chapter),
    );
    return FutureBuilder<String>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final html = snapshot.data ?? '';
        final foreground = SettingsStore.textFor(settings.theme);
        final baseTheme = Theme.of(context);
        final textTheme = baseTheme.textTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        );
        final updatedTextTheme = textTheme.copyWith(
          bodyMedium: textTheme.bodyMedium?.copyWith(
            fontSize: settings.fontSize,
            height: 1.6,
          ),
          bodyLarge: textTheme.bodyLarge?.copyWith(
            fontSize: settings.fontSize + 2,
            height: 1.6,
          ),
          bodySmall: textTheme.bodySmall?.copyWith(
            fontSize: settings.fontSize - 2,
            height: 1.6,
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _restoreChapterPosition(index);
        });
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis != Axis.vertical) {
              return false;
            }
            if (notification is ScrollEndNotification) {
              _scheduleProgressSave();
            }
            if (notification is ScrollUpdateNotification &&
                notification.metrics.maxScrollExtent > 0) {
              _chapterProgress[index] =
                  (notification.metrics.pixels /
                          notification.metrics.maxScrollExtent)
                      .clamp(0.0, 1.0);
            }
            return false;
          },
          child: KeyedSubtree(
            key: _scrollKeyForChapter(index),
            child: ReaderSelectionAutoScroll(
              controller: _controllerForChapter(index),
              selectionActive: _selectionActive,
              child: SingleChildScrollView(
                controller: _controllerForChapter(index),
                key: PageStorageKey('epub-chapter-${chapter.cacheKey}'),
                padding: const EdgeInsets.all(16),
                child: Theme(
                  data: baseTheme.copyWith(textTheme: updatedTextTheme),
                  child: _buildHtmlWidget(
                    html,
                    settings,
                    index,
                    _controllerForChapter(index),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _restoreChapterPosition(int index) {
    if (_restoredChapters.contains(index)) return;
    final controller = _scrollControllers[index];
    if (controller == null || !controller.hasClients) return;
    final max = controller.position.maxScrollExtent;
    if (max <= 0) return;
    double? progress = _chapterProgress[index];
    if (progress == null) {
      final offset = _chapterOffsets[index];
      if (offset != null && offset > 0) {
        progress = (offset / max).clamp(0.0, 1.0);
        _chapterProgress[index] = progress;
      }
    }
    if (progress != null && progress >= 0 && progress <= 1) {
      final target = (max * progress).clamp(0.0, max);
      controller.jumpTo(target);
      _restoredChapters.add(index);
    }
  }

  Widget _buildHtmlWidget(
    String html,
    ReaderSettings settings,
    int chapterIndex,
    ScrollController controller,
  ) {
    final source = html.isEmpty ? '<p></p>' : html;
    final cacheKey = _chapters[chapterIndex].cacheKey;
    final blocks = _chapterBlocksCache.putIfAbsent(
      cacheKey,
      () => _parseHtmlBlocks(source),
    );
    final keys = _blockKeysForChapter(chapterIndex, blocks.length);
    final textStyle = TextStyle(
      fontSize: settings.fontSize,
      height: 1.6,
      color: SettingsStore.textFor(settings.theme),
    );
    return ReaderSelectionAutoScroll(
      controller: controller,
      selectionActive: _selectionActive,
      child: SelectionArea(
        onSelectionChanged: (content) {
          final text = content?.plainText.trim() ?? '';
          _selectedText = text;
          _selectionActive.value = text.isNotEmpty;
        },
        contextMenuBuilder: (context, selectableRegionState) {
          final items = List<ContextMenuButtonItem>.from(
            selectableRegionState.contextMenuButtonItems,
          );
          final localizedItems = items.map(_localizedMenuItem).toList();
          localizedItems.add(
            ContextMenuButtonItem(
              label: '分享',
              onPressed: () {
                final selectedText = _shareTextForSelection(
                  _selectedText,
                  chapterIndex,
                );
                selectableRegionState.hideToolbar();
                if (selectedText.isEmpty) return;
                _openShareSheet(selectedText, sourceLabel: '已选文字');
              },
            ),
          );
          localizedItems.add(
            ContextMenuButtonItem(
              label: 'AI问答',
              onPressed: () {
                final selectedText = _selectedText;
                selectableRegionState.hideToolbar();
                _openAiChat(quote: selectedText);
              },
            ),
          );
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: selectableRegionState.contextMenuAnchors,
            buttonItems: localizedItems,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < blocks.length; i++)
              if (blocks[i].imageBytes != null)
                Padding(
                  key: keys[i],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Image.memory(
                    blocks[i].imageBytes!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                )
              else if (blocks[i].text != null &&
                  blocks[i].text!.trim().isNotEmpty)
                Padding(
                  key: keys[i],
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildTranslatedTextBlock(
                    text: blocks[i].text!,
                    textStyle: textStyle,
                  ),
                ),
          ],
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

  List<GlobalKey> _blockKeysForChapter(int index, int count) {
    final existing = _blockKeys[index];
    if (existing != null && existing.length == count) {
      return existing;
    }
    final created = List<GlobalKey>.generate(count, (_) => GlobalKey());
    _blockKeys[index] = created;
    return created;
  }

  GlobalKey _scrollKeyForChapter(int index) {
    return _scrollKeys.putIfAbsent(index, () => GlobalKey());
  }

  Future<void> _shareCurrentScreen() async {
    final visibleText = _collectVisibleText(_currentChapter);
    String text = visibleText.trim();
    if (text.isEmpty) {
      text = _chapterText(_currentChapter);
    }
    text = _trimShareText(text);
    if (text.isEmpty) {
      _showSnack('当前页面内容尚未加载');
      return;
    }
    await _openShareSheet(text, sourceLabel: '当前屏幕');
  }

  String _chapterText(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return '';
    final cacheKey = _chapters[chapterIndex].cacheKey;
    final blocks = _chapterBlocksCache[cacheKey];
    if (blocks == null || blocks.isEmpty) return '';
    return blocks
        .where((block) => block.text != null && block.text!.trim().isNotEmpty)
        .map((block) => block.text!.trim())
        .join('\n\n');
  }

  String _collectVisibleText(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return '';
    final cacheKey = _chapters[chapterIndex].cacheKey;
    final blocks = _chapterBlocksCache[cacheKey];
    final keys = _blockKeys[chapterIndex];
    if (blocks == null || keys == null || blocks.length != keys.length) {
      return '';
    }
    final scrollBox =
        _scrollKeyForChapter(chapterIndex).currentContext?.findRenderObject()
            as RenderBox?;
    if (scrollBox == null) return '';
    final viewport = scrollBox.localToGlobal(Offset.zero) & scrollBox.size;
    final buffer = StringBuffer();
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.text == null || block.text!.trim().isEmpty) continue;
      final box = keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.overlaps(viewport)) {
        buffer.write(block.text!.trim());
        buffer.write('\n\n');
      }
    }
    return buffer.toString().trim();
  }

  String _trimShareText(String text) {
    return _normalizeShareText(text);
  }

  String _shareTextForSelection(String text, int chapterIndex) {
    final normalizedSelected = _normalizeCompactText(text);
    if (normalizedSelected.isEmpty) {
      return _normalizeShareText(text);
    }
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) {
      return _normalizeShareText(text);
    }
    final cacheKey = _chapters[chapterIndex].cacheKey;
    final blocks = _chapterBlocksCache[cacheKey];
    if (blocks == null || blocks.isEmpty) {
      return _normalizeShareText(text);
    }
    final paragraphs = <String>[];
    final compactParagraphs = <String>[];
    for (final block in blocks) {
      final paragraph = block.text?.trim();
      if (paragraph == null || paragraph.isEmpty) continue;
      final normalizedParagraph = _normalizeCompactText(paragraph);
      if (normalizedParagraph.isEmpty) continue;
      paragraphs.add(paragraph);
      compactParagraphs.add(normalizedParagraph);
    }
    if (paragraphs.isEmpty) {
      return _normalizeShareText(text);
    }
    final joinedCompact = compactParagraphs.join();
    final startOffset = joinedCompact.indexOf(normalizedSelected);
    if (startOffset == -1) {
      return _normalizeShareText(text);
    }
    final endOffset = startOffset + normalizedSelected.length;

    var compactCursor = 0;
    final selectedParagraphs = <String>[];
    for (var i = 0; i < paragraphs.length; i++) {
      final compact = compactParagraphs[i];
      final paragraphStart = compactCursor;
      final paragraphEnd = paragraphStart + compact.length;
      compactCursor = paragraphEnd;

      if (endOffset <= paragraphStart || startOffset >= paragraphEnd) {
        continue;
      }

      final localStart = startOffset <= paragraphStart
          ? 0
          : startOffset - paragraphStart;
      final localEnd = endOffset >= paragraphEnd
          ? compact.length
          : endOffset - paragraphStart;
      final slice = _sliceParagraphByCompactOffsets(
        paragraphs[i],
        localStart,
        localEnd,
      );
      if (slice.isNotEmpty) {
        selectedParagraphs.add(slice);
      }
    }
    if (selectedParagraphs.isNotEmpty) {
      return selectedParagraphs.join('\n\n');
    }
    return _normalizeShareText(text);
  }

  String _normalizeShareText(String text) {
    final paragraphs = _translationService.splitParagraphs(text);
    if (paragraphs.isEmpty) return text.trim();
    return paragraphs.join('\n\n').trim();
  }

  String _normalizeCompactText(String text) {
    return text.replaceAll(RegExp(r'\s+'), '');
  }

  String _sliceParagraphByCompactOffsets(
    String paragraph,
    int compactStart,
    int compactEnd,
  ) {
    if (compactStart >= compactEnd) return '';
    var compactIndex = 0;
    int? startIndex;
    var endIndex = paragraph.length;

    for (var i = 0; i < paragraph.length; i++) {
      final char = paragraph[i];
      if (RegExp(r'\s').hasMatch(char)) {
        continue;
      }
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
    return paragraph.substring(startIndex, endIndex).trim();
  }

  Future<void> _openShareSheet(
    String text, {
    required String sourceLabel,
  }) async {
    final bookRef = _bookRef;
    final title = (bookRef?.Title?.trim().isNotEmpty ?? false)
        ? bookRef!.Title!.trim()
        : widget.book.title;
    final author = (bookRef?.Author?.trim().isNotEmpty ?? false)
        ? bookRef!.Author!.trim()
        : '未知作者';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReaderShareSheet(
        title: title,
        author: author,
        text: text,
        sourceLabel: sourceLabel,
        messenger: ScaffoldMessenger.of(this.context),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _isCurrentChapterTranslating =>
      _translatingChapters.contains(_currentChapter);

  Widget _buildTranslatedTextBlock({
    required String text,
    required TextStyle textStyle,
  }) {
    final translation = _translations[_translationService.paragraphKey(text)];
    final hasTranslation =
        translation != null &&
        translation.trim().isNotEmpty &&
        translation.trim() != text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$text\n', style: textStyle),
        if (hasTranslation)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${translation.trim()}\n',
              style: textStyle.copyWith(
                fontSize: textStyle.fontSize != null
                    ? textStyle.fontSize! * 0.96
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _translateCurrentChapter() async {
    if (!_translationEnabled) {
      _translationEnabled = true;
      unawaited(
        PersistentKvStore.instance.setBool(
          '$_translationModeKeyPrefix${widget.book.id}',
          true,
        ),
      );
      if (mounted) {
        setState(() {});
      }
    }
    try {
      await _translateChapterIfNeeded(_currentChapter, forceRefresh: true);
    } catch (error) {
      _showSnack('翻译失败：$error');
    }
    _enqueueTranslationAround(centerChapter: _currentChapter);
  }

  Future<AiChatApiSettings> _loadTranslationSettings({
    bool refresh = false,
  }) async {
    final current = _translationSettings;
    if (!refresh && current != null) return current;
    final loaded = await _aiApiStore.load();
    final changed =
        current == null ||
        current.provider != loaded.provider ||
        current.effectiveBaseUrl() != loaded.effectiveBaseUrl() ||
        current.effectiveModel() != loaded.effectiveModel();
    _translationSettings = loaded;
    if (changed) {
      _translations
        ..clear()
        ..addAll(
          await _translationCacheStore.load(
            bookId: widget.book.id,
            settings: loaded,
          ),
        );
      if (mounted) {
        setState(() {});
      }
    }
    return loaded;
  }

  void _schedulePersistTranslations() {
    _translationSaveTimer?.cancel();
    _translationSaveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_persistTranslations());
    });
  }

  Future<void> _persistTranslations() async {
    final settings = _translationSettings;
    if (settings == null) return;
    await _translationCacheStore.saveAll(
      bookId: widget.book.id,
      settings: settings,
      entries: _translations,
    );
  }

  void _enqueueTranslationAround({required int centerChapter}) {
    _translationQueue = _translationQueue.then((_) async {
      if (_chapters.isEmpty) return;
      final last = _chapters.length - 1;
      final targets = <int>{
        centerChapter.clamp(0, last),
        (centerChapter - 1).clamp(0, last),
        (centerChapter + 1).clamp(0, last),
      }.toList()..sort();
      for (final index in targets) {
        if (!_translationEnabled) return;
        try {
          await _translateChapterIfNeeded(index, forceRefresh: false);
        } catch (_) {
          // Ignore background translation errors for adjacent chapters.
        }
      }
    });
  }

  Future<void> _translateChapterIfNeeded(
    int chapterIndex, {
    required bool forceRefresh,
  }) {
    final inFlight = _inFlightTranslations[chapterIndex];
    if (inFlight != null) return inFlight;
    final future = _translateChapterIfNeededInternal(
      chapterIndex,
      forceRefresh: forceRefresh,
    );
    _inFlightTranslations[chapterIndex] = future;
    return future.whenComplete(
      () => _inFlightTranslations.remove(chapterIndex),
    );
  }

  Future<void> _translateChapterIfNeededInternal(
    int chapterIndex, {
    required bool forceRefresh,
  }) async {
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return;
    final bookRef = _bookRef;
    final settings = _settings;
    if (bookRef == null || settings == null) return;
    final chapter = _chapters[chapterIndex];
    final html = await _chapterHtmlCache.putIfAbsent(
      chapter.cacheKey,
      () => _buildChapterHtml(bookRef, settings, chapter),
    );
    final blocks = _chapterBlocksCache.putIfAbsent(
      chapter.cacheKey,
      () => _parseHtmlBlocks(html.isEmpty ? '<p></p>' : html),
    );
    final paragraphs = blocks
        .map((block) => block.text?.trim() ?? '')
        .where((text) => text.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return;
    final hasNonChinese = paragraphs.any(
      (text) => !_translationService.isLikelyChinese(text),
    );
    if (!hasNonChinese) {
      if (chapterIndex == _currentChapter && mounted) {
        setState(() {});
      }
      return;
    }
    final missing = paragraphs.where((text) {
      if (_translationService.isLikelyChinese(text)) return false;
      return !_translations.containsKey(_translationService.paragraphKey(text));
    }).toList();
    if (missing.isEmpty) {
      if (chapterIndex == _currentChapter && mounted) {
        setState(() {});
      }
      return;
    }
    final translationSettings = await _loadTranslationSettings(
      refresh: forceRefresh,
    );
    if (mounted) {
      setState(() {
        _translatingChapters.add(chapterIndex);
      });
    } else {
      _translatingChapters.add(chapterIndex);
    }
    try {
      final translated = await _translationService.translateParagraphs(
        settings: translationSettings,
        paragraphs: missing,
      );
      if (translated.isEmpty) return;
      _translations.addAll(translated);
      _schedulePersistTranslations();
      if (chapterIndex == _currentChapter && mounted) {
        setState(() {});
      }
    } finally {
      _translatingChapters.remove(chapterIndex);
      if (chapterIndex == _currentChapter && mounted) {
        setState(() {});
      }
    }
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

  List<_HtmlBlock> _parseHtmlBlocks(String html) {
    final blocks = <_HtmlBlock>[];
    final imgTag = RegExp(r'<img[^>]*>', caseSensitive: false, multiLine: true);
    var cursor = 0;
    for (final match in imgTag.allMatches(html)) {
      final before = html.substring(cursor, match.start);
      _appendTextBlocks(blocks, before);

      final tag = match.group(0) ?? '';
      final srcMatch = RegExp(
        r'''src\s*=\s*(["'])(.*?)\1|src\s*=\s*([^\s>]+)''',
        caseSensitive: false,
      ).firstMatch(tag);
      final src = srcMatch?.group(2) ?? srcMatch?.group(3);
      final bytes = src == null ? null : _decodeDataImage(src);
      if (bytes != null) {
        blocks.add(_HtmlBlock(imageBytes: bytes));
      }
      cursor = match.end;
    }
    if (cursor < html.length) {
      _appendTextBlocks(blocks, html.substring(cursor));
    }
    return blocks;
  }

  void _appendTextBlocks(List<_HtmlBlock> blocks, String html) {
    final text = _htmlToPlainTextPreserveParagraphs(html);
    if (text.isEmpty) return;
    final paragraphs = text.split('\n\n');
    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) continue;
      blocks.add(_HtmlBlock(text: trimmed));
    }
  }

  String _htmlToPlainTextPreserveParagraphs(String html) {
    var text = html;
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(
      RegExp(
        r'</(p|div|section|article|h[1-6]|li|blockquote)>',
        caseSensitive: false,
      ),
      '\n\n',
    );
    text = text.replaceAll(
      RegExp(
        r'<(p|div|section|article|h[1-6]|li|blockquote)[^>]*>',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
    text = text.replaceAll('&nbsp;', ' ');
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('\r\n', '\n');
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  Uint8List? _decodeDataImage(String src) {
    final lower = src.toLowerCase();
    if (!lower.startsWith('data:image/')) return null;
    final index = src.indexOf('base64,');
    if (index == -1) return null;
    final b64 = src.substring(index + 7).trim();
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  void _warmChapter(int index) {
    final bookRef = _bookRef;
    final settings = _settings;
    if (bookRef == null || settings == null) return;
    final targets = [index, if (index + 1 < _chapters.length) index + 1];
    for (final i in targets) {
      final chapter = _chapters[i];
      _chapterHtmlCache.putIfAbsent(
        chapter.cacheKey,
        () => _buildChapterHtml(bookRef, settings, chapter),
      );
    }
  }

  List<_EpubChapterEntry> _flattenChapters(List<EpubChapterRef> roots) {
    final result = <_EpubChapterEntry>[];
    void visit(List<EpubChapterRef> items) {
      for (final chapter in items) {
        final title = (chapter.Title?.trim().isNotEmpty ?? false)
            ? chapter.Title!.trim()
            : '未命名章节';
        result.add(
          _EpubChapterEntry.fromRef(title: title, chapterRef: chapter),
        );
        final subs = chapter.SubChapters;
        if (subs != null && subs.isNotEmpty) {
          visit(subs);
        }
      }
    }

    visit(roots);
    return result;
  }

  Future<List<_EpubChapterEntry>> _buildChapters(
    EpubBookRef bookRef,
    List<EpubChapterRef> chapterRefs,
  ) async {
    final fromToc = _flattenChapters(chapterRefs);
    final fromSpine = await _chaptersFromSpine(bookRef, fromToc);
    if (fromToc.isEmpty) return fromSpine;
    if (fromToc.length <= 1 && fromSpine.length > fromToc.length) {
      return fromSpine;
    }
    return fromToc;
  }

  Future<List<_EpubChapterEntry>> _chaptersFromSpine(
    EpubBookRef bookRef,
    List<_EpubChapterEntry> fromToc,
  ) async {
    final itemRefs = bookRef.Schema?.Package?.Spine?.Items ?? [];
    final manifestItems = bookRef.Schema?.Package?.Manifest?.Items ?? [];
    if (itemRefs.isEmpty || manifestItems.isEmpty) return fromToc;

    final manifestById = <String, dynamic>{};
    for (final item in manifestItems) {
      final id = (item.Id ?? '').trim();
      if (id.isEmpty) continue;
      manifestById[id.toLowerCase()] = item;
    }

    final result = <_EpubChapterEntry>[];
    for (var i = 0; i < itemRefs.length; i++) {
      final idRef = (itemRefs[i].IdRef ?? '').toLowerCase();
      if (idRef.isEmpty) continue;
      final manifestItem = manifestById[idRef];
      if (manifestItem == null) continue;

      final href = (manifestItem.Href ?? '').trim();
      if (href.isEmpty) continue;

      final media = (manifestItem.MediaType ?? '').toLowerCase();
      final isHtml = media.contains('xhtml') || media.contains('html');
      if (!isHtml) continue;

      final html = await _readHtmlFromHref(bookRef, href);
      if (html == null || html.trim().isEmpty) continue;

      result.add(
        _EpubChapterEntry.fromHref(
          title: _titleFromHref(href, i + 1),
          contentHref: href,
        ),
      );
    }
    return result.isEmpty ? fromToc : result;
  }

  String _titleFromHref(String href, int index) {
    final file = p.basenameWithoutExtension(href).trim();
    if (file.isEmpty) return '章节 $index';
    final lower = file.toLowerCase();
    if (lower.contains('titlepage') || lower.contains('cover')) return '封面';
    return file;
  }

  Future<String> _buildChapterHtml(
    EpubBookRef bookRef,
    ReaderSettings settings,
    _EpubChapterEntry chapter,
  ) async {
    try {
      String html;
      String? baseHref;
      final chapterRef = chapter.chapterRef;
      if (chapterRef != null) {
        html = await chapterRef.readHtmlContent();
        baseHref = chapterRef.ContentFileName;
      } else {
        baseHref = chapter.contentHref;
        html = await _readHtmlFromHref(bookRef, baseHref) ?? '';
      }
      if (html.trim().isEmpty) return '';
      html = _normalizeHtml(html);
      html = _stripCss(html);
      html = await _resolveImages(bookRef, html, baseHref);
      return html;
    } catch (_) {
      return '';
    }
  }

  Future<String?> _readHtmlFromHref(EpubBookRef bookRef, String? href) async {
    if (href == null || href.isEmpty) return null;
    final htmlMap = bookRef.Content?.Html ?? {};
    final normalized = href.replaceFirst(RegExp(r'^\./'), '');
    final ref = htmlMap[href] ?? htmlMap[normalized];
    if (ref != null) {
      return ref.readContentAsText();
    }
    for (final entry in htmlMap.entries) {
      if (entry.key.endsWith(normalized)) {
        return entry.value.readContentAsText();
      }
    }
    return null;
  }

  String _normalizeHtml(String html) {
    var normalized = html;
    if (!normalized.contains('<html') && !normalized.contains('<body')) {
      normalized = '<html><body>$normalized</body></html>';
    }
    if (!normalized.contains('<p') && normalized.contains('\n')) {
      normalized = normalized.replaceAll('\n', '<br/>');
    }
    return normalized;
  }

  String _stripCss(String html) {
    var cleaned = html;
    cleaned = cleaned.replaceAll(
      RegExp(r'<head[^>]*>[\s\S]*?<\/head>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<style[^>]*>[\s\S]*?<\/style>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'''<link[^>]+rel=["']?stylesheet["']?[^>]*>''',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'''\sstyle\s*=\s*(".*?"|'.*?'|[^\s>]+)''', caseSensitive: false),
      '',
    );
    return cleaned;
  }

  Future<String> _resolveImages(
    EpubBookRef bookRef,
    String html,
    String? baseHref,
  ) async {
    if (baseHref == null || baseHref.isEmpty) return html;
    final imgTag = RegExp(
      r'''<img[^>]+src\s*=\s*(["']?)([^"'\s>]+)\1''',
      caseSensitive: false,
    );
    final matches = imgTag.allMatches(html).toList();
    if (matches.isEmpty) return html;
    final buffer = StringBuffer();
    var lastIndex = 0;
    for (final match in matches) {
      buffer.write(html.substring(lastIndex, match.start));
      final original = match.group(0) ?? '';
      final src = match.group(2) ?? '';
      final resolved = await _resolveImageSrc(bookRef, src, baseHref);
      if (resolved == null) {
        buffer.write(original);
      } else {
        buffer.write(original.replaceFirst(src, resolved));
      }
      lastIndex = match.end;
    }
    buffer.write(html.substring(lastIndex));
    return buffer.toString();
  }

  Future<String?> _resolveImageSrc(
    EpubBookRef bookRef,
    String src,
    String baseHref,
  ) async {
    if (src.isEmpty) return null;
    if (src.startsWith('http') ||
        src.startsWith('data:') ||
        src.startsWith('//')) {
      return null;
    }
    var clean = src.split('#').first.split('?').first;
    if (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    final baseDir = p.dirname(baseHref);
    final resolved = p.normalize(p.join(baseDir, clean));
    final cacheKey = resolved;
    final cached = _imageCache[cacheKey];
    if (cached != null) return cached;
    final images = bookRef.Content?.Images ?? {};
    dynamic ref = images[resolved] ?? images[clean];
    if (ref == null) {
      final normalized = resolved.replaceFirst(RegExp(r'^\./'), '');
      ref = images[normalized];
      ref ??= images[clean.replaceFirst(RegExp(r'^\./'), '')];
      if (ref == null) {
        for (final entry in images.entries) {
          if (entry.key.endsWith(normalized)) {
            ref = entry.value;
            break;
          }
        }
      }
    }
    if (ref == null) return null;
    final bytes = await ref.readContentAsBytes();
    final mime = ref.ContentMimeType ?? _guessMimeType(ref.FileName ?? clean);
    final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';
    _imageCache[cacheKey] = dataUri;
    return dataUri;
  }

  String _guessMimeType(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.svg':
        return 'image/svg+xml';
      case '.webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }
}

class _EpubChapterEntry {
  _EpubChapterEntry.fromRef({required this.title, required this.chapterRef})
    : contentHref = null;

  _EpubChapterEntry.fromHref({required this.title, required this.contentHref})
    : chapterRef = null;

  final String title;
  final EpubChapterRef? chapterRef;
  final String? contentHref;

  String get baseHref => chapterRef?.ContentFileName ?? contentHref ?? '';

  String get cacheKey => '$baseHref#${chapterRef?.Anchor ?? ''}';
}

class _HtmlBlock {
  _HtmlBlock({this.text, this.imageBytes});

  final String? text;
  final Uint8List? imageBytes;
}
