import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:epubx/epubx.dart' show EpubBookRef, EpubChapterRef, EpubReader;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

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

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;

  ReaderSettings? _settings;
  EpubBookRef? _bookRef;
  List<_EpubChapterEntry> _chapters = [];
  PageController? _pageController;
  int _currentChapter = 0;
  final Map<String, String> _imageCache = {};
  final Map<String, Future<String>> _chapterHtmlCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    _pageController?.dispose();
    super.dispose();
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
    _pageController?.dispose();
    _pageController = PageController(initialPage: safeInitial);
    _settings = settings;
    _bookRef = bookRef;
    _chapters = chapters;
    _currentChapter = safeInitial;
    if (mounted) {
      setState(() {});
    }
    _warmChapter(safeInitial);
  }

  Future<void> _saveProgress() async {
    await _store.updateBookProgress(widget.book.id, lastPage: _currentChapter);
  }

  void _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    final updated = await showModalBottomSheet<ReaderSettings>(
      context: context,
      builder: (context) => ReaderSettingsSheet(settings: settings),
    );
    if (updated == null) return;
    await _settingsStore.save(updated);
    setState(() {
      _settings = updated;
      _chapterHtmlCache.clear();
    });
    _warmChapter(_currentChapter);
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
    return ReaderLayout(
      book: widget.book,
      settings: settings,
      actions: [
        IconButton(
          onPressed: _openToc,
          icon: const Icon(Icons.list),
          tooltip: '目录',
        ),
        IconButton(
          onPressed: _openSettings,
          icon: const Icon(Icons.text_fields),
          tooltip: '阅读设置',
        ),
      ],
      child: _chapters.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                _currentChapter = index;
                _warmChapter(index);
              },
              itemCount: _chapters.length,
              itemBuilder: (context, index) =>
                  _buildChapterPage(context, bookRef, settings, index),
            ),
    );
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
        return SingleChildScrollView(
          key: PageStorageKey('epub-chapter-${chapter.cacheKey}'),
          padding: const EdgeInsets.all(16),
          child: Theme(
            data: baseTheme.copyWith(textTheme: updatedTextTheme),
            child: _buildHtmlWidget(html, settings),
          ),
        );
      },
    );
  }

  Widget _buildHtmlWidget(String html, ReaderSettings settings) {
    final source = html.isEmpty ? '<p></p>' : html;
    final blocks = _parseHtmlBlocks(source);
    final textStyle = TextStyle(
      fontSize: settings.fontSize,
      height: 1.6,
      color: SettingsStore.textFor(settings.theme),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks)
          if (block.imageBytes != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Image.memory(
                block.imageBytes!,
                fit: BoxFit.contain,
              ),
            )
          else if (block.text != null && block.text!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(block.text!, style: textStyle),
            ),
      ],
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
