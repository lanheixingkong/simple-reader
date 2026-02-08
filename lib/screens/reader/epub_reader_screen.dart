import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:epubx/epubx.dart' show EpubBookRef, EpubChapterRef, EpubReader;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/library.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import 'reader_layout.dart';
import 'reader_settings_sheet.dart';

class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen>
    with WidgetsBindingObserver {
  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;

  ReaderSettings? _settings;
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
  String _selectedText = '';
  Timer? _saveTimer;
  Timer? _progressSaveTimer;
  final ValueNotifier<bool> _showChrome = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _pageScrollEnabled = ValueNotifier<bool>(true);
  late final ScrollPhysics _pagePhysics = _ToggleableScrollPhysics(
    _pageScrollEnabled,
    parent: const PageScrollPhysics(),
  );
  Offset? _tapDownPosition;
  DateTime? _tapDownTime;

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
    _showChrome.dispose();
    _pageScrollEnabled.dispose();
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
    final settings = await _settingsStore.load();
    final bytes = await File(widget.book.path).readAsBytes();
    final bookRef = await EpubReader.openBook(bytes);
    final chapterRefs = await bookRef.getChapters();
    final chapters = _flattenChapters(chapterRefs);
    final initialPage = widget.book.lastPage ?? 0;
    final safeInitial =
        chapters.isEmpty ? 0 : initialPage.clamp(0, chapters.length - 1);
    final rawOffset = widget.book.lastOffset ?? 0.0;
    final initialOffset = rawOffset < 0 ? 0.0 : rawOffset;
    final rawProgress = widget.book.lastProgress;
    if (rawProgress != null && rawProgress >= 0 && rawProgress <= 1) {
      _chapterProgress[safeInitial] = rawProgress;
    }
    _pageController?.dispose();
    _pageController = PageController(initialPage: safeInitial);
    _settings = settings;
    _bookRef = bookRef;
    _chapters = chapters;
    _currentChapter = safeInitial;
    _chapterOffsets[safeInitial] = initialOffset;
    if (mounted) {
      setState(() {});
    }
    _warmChapter(safeInitial);
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
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(
      const Duration(milliseconds: 500),
      _saveProgress,
    );
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
        final max = controller.hasClients ? controller.position.maxScrollExtent : 0.0;
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final bookRef = _bookRef;
    if (settings == null || bookRef == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return WillPopScope(
      onWillPop: () async {
        await _saveProgress();
        return true;
      },
      child: ReaderLayout(
        book: widget.book,
        settings: settings,
        showAppBarListenable: _showChrome,
        actions: [
          IconButton(
            onPressed: _openToc,
            icon: const Icon(Icons.list),
            tooltip: '目录',
          ),
          IconButton(
            onPressed: _shareCurrentScreen,
            icon: const Icon(Icons.ios_share),
            tooltip: '分享',
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.text_fields),
            tooltip: '阅读设置',
          ),
        ],
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _tapDownPosition = event.position;
            _tapDownTime = DateTime.now();
          },
          onPointerUp: (event) {
            _handleTapToggle(event.position);
          },
          child: _chapters.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : PageView.builder(
                  controller: _pageController,
                  physics: _pagePhysics,
                  onPageChanged: (index) {
                    _currentChapter = index;
                    _chapterOffsets.putIfAbsent(index, () => 0.0);
                    _chapterProgress.putIfAbsent(index, () => 0.0);
                    _scheduleProgressSave();
                    _warmChapter(index);
                  },
                  itemCount: _chapters.length,
                  itemBuilder: (context, index) =>
                      _buildChapterPage(context, bookRef, settings, index),
                ),
        ),
      ),
    );
  }

  void _handleTapToggle(Offset upPosition) {
    final downPosition = _tapDownPosition;
    final downTime = _tapDownTime;
    _tapDownPosition = null;
    _tapDownTime = null;
    if (downPosition == null || downTime == null) return;
    final distance = (upPosition - downPosition).distance;
    final elapsed = DateTime.now().difference(downTime);
    if (distance <= 12 && elapsed.inMilliseconds <= 280) {
      _showChrome.value = !_showChrome.value;
    }
  }

  Widget _buildChapterPage(BuildContext context, EpubBookRef bookRef,
      ReaderSettings settings, int index) {
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
            if (notification is ScrollStartNotification) {
              _setPageScrollEnabled(false);
            } else if (notification is ScrollEndNotification) {
              _setPageScrollEnabled(true);
              _scheduleProgressSave();
            }
            if (notification is ScrollUpdateNotification &&
                notification.metrics.maxScrollExtent > 0) {
              _chapterProgress[index] = (notification.metrics.pixels /
                      notification.metrics.maxScrollExtent)
                  .clamp(0.0, 1.0);
            }
            return false;
          },
          child: KeyedSubtree(
            key: _scrollKeyForChapter(index),
            child: SingleChildScrollView(
              controller: _controllerForChapter(index),
              key: PageStorageKey('epub-chapter-${chapter.cacheKey}'),
              padding: const EdgeInsets.all(16),
              child: Theme(
                data: baseTheme.copyWith(textTheme: updatedTextTheme),
                child: _buildHtmlWidget(html, settings, index),
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
      String html, ReaderSettings settings, int chapterIndex) {
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
    return SelectionArea(
      onSelectionChanged: (content) {
        _selectedText = content?.plainText.trim() ?? '';
      },
      contextMenuBuilder: (context, selectableRegionState) {
        final items = List<ContextMenuButtonItem>.from(
          selectableRegionState.contextMenuButtonItems ?? const [],
        );
        items.add(
          ContextMenuButtonItem(
            label: '分享',
            onPressed: () {
              final selectedText = _selectedText;
              selectableRegionState.hideToolbar();
              if (selectedText.isEmpty) return;
              _openShareSheet(
                selectedText,
                sourceLabel: '已选文字',
              );
            },
          ),
        );
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: items,
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
            else if (blocks[i].text != null && blocks[i].text!.trim().isNotEmpty)
              Padding(
                key: keys[i],
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('${blocks[i].text!}\n', style: textStyle),
              ),
        ],
      ),
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
    return text.trim();
  }

  Future<void> _openShareSheet(String text, {required String sourceLabel}) async {
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
      builder: (context) => _ReaderShareSheet(
        title: title,
        author: author,
        text: text,
        sourceLabel: sourceLabel,
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<_HtmlBlock> _parseHtmlBlocks(String html) {
    final blocks = <_HtmlBlock>[];
    final imgTag =
        RegExp(r'<img[^>]*>', caseSensitive: false, multiLine: true);
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
      RegExp(r'</(p|div|section|article|h[1-6]|li|blockquote)>',
          caseSensitive: false),
      '\n\n',
    );
    text = text.replaceAll(
      RegExp(r'<(p|div|section|article|h[1-6]|li|blockquote)[^>]*>',
          caseSensitive: false),
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
    final targets = [
      index,
      if (index + 1 < _chapters.length) index + 1,
    ];
    for (final i in targets) {
      final chapter = _chapters[i];
      _chapterHtmlCache.putIfAbsent(
        chapter.cacheKey,
        () => _buildChapterHtml(bookRef, settings, chapter),
      );
    }
  }

  void _setPageScrollEnabled(bool enabled) {
    if (_pageScrollEnabled.value == enabled) return;
    _pageScrollEnabled.value = enabled;
  }

  List<_EpubChapterEntry> _flattenChapters(List<EpubChapterRef> roots) {
    final result = <_EpubChapterEntry>[];
    void visit(List<EpubChapterRef> items) {
      for (final chapter in items) {
        final title = (chapter.Title?.trim().isNotEmpty ?? false)
            ? chapter.Title!.trim()
            : '未命名章节';
        result.add(_EpubChapterEntry(
          title: title,
          chapterRef: chapter,
        ));
        final subs = chapter.SubChapters;
        if (subs != null && subs.isNotEmpty) {
          visit(subs);
        }
      }
    }

    visit(roots);
    return result;
  }

  Future<String> _buildChapterHtml(EpubBookRef bookRef,
      ReaderSettings settings, _EpubChapterEntry chapter) async {
    try {
      var html = await chapter.chapterRef.readHtmlContent();
      if (html.trim().isEmpty) return '';
      html = _normalizeHtml(html);
      html = _stripCss(html);
      html = await _resolveImages(
        bookRef,
        html,
        chapter.chapterRef.ContentFileName,
      );
      return html;
    } catch (_) {
      return '';
    }
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
      RegExp(
        r'''\sstyle\s*=\s*(".*?"|'.*?'|[^\s>]+)''',
        caseSensitive: false,
      ),
      '',
    );
    return cleaned;
  }

  Future<String> _resolveImages(
      EpubBookRef bookRef, String html, String? baseHref) async {
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
      EpubBookRef bookRef, String src, String baseHref) async {
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

  String _colorToCss(Color color) {
    return 'rgba(${color.red}, ${color.green}, ${color.blue}, ${color.opacity})';
  }
}

class _EpubChapterEntry {
  _EpubChapterEntry({
    required this.title,
    required this.chapterRef,
  });

  final String title;
  final EpubChapterRef chapterRef;

  String get cacheKey =>
      '${chapterRef.ContentFileName ?? 'unknown'}#${chapterRef.Anchor ?? ''}';
}

class _HtmlBlock {
  _HtmlBlock({this.text, this.imageBytes});

  final String? text;
  final Uint8List? imageBytes;
}

class _ReaderShareSheet extends StatefulWidget {
  const _ReaderShareSheet({
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
  State<_ReaderShareSheet> createState() => _ReaderShareSheetState();
}

class _ReaderShareSheetState extends State<_ReaderShareSheet> {
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
    return Container(
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
    final textStyle = const TextStyle(fontSize: 16, height: 1.7);
    final titleStyle = const TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    final authorStyle = const TextStyle(fontSize: 13);
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

class _ToggleableScrollPhysics extends ScrollPhysics {
  const _ToggleableScrollPhysics(this.enabledListenable, {ScrollPhysics? parent})
      : super(parent: parent);

  final ValueListenable<bool> enabledListenable;

  bool get _enabled => enabledListenable.value;

  @override
  _ToggleableScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ToggleableScrollPhysics(
      enabledListenable,
      parent: buildParent(ancestor),
    );
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (!_enabled) return false;
    return super.shouldAcceptUserOffset(position);
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (!_enabled) return 0.0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if (!_enabled) return null;
    return super.createBallisticSimulation(position, velocity);
  }
}
