import 'dart:io';
import 'dart:math';

import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdfx/pdfx.dart';

import '../models/library.dart';
import '../services/library_store.dart';
import '../services/settings_store.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;

  ReaderSettings? _settings;
  List<String> _textPages = [];
  List<_EpubChapter> _epubChapters = [];
  PdfControllerPinch? _pdfController;
  ScrollController? _scrollController;
  PageController? _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    _pdfController?.dispose();
    _scrollController?.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    _settings = settings;
    if (widget.book.format == BookFormat.pdf) {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(widget.book.path),
        initialPage: max(1, widget.book.lastPage ?? 1),
      );
    } else if (widget.book.format == BookFormat.txt) {
      final raw = await File(widget.book.path).readAsString();
      _textPages = _paginateText(raw, settings.fontSize);
      _currentPage = widget.book.lastPage ?? 0;
      _pageController = PageController(initialPage: _currentPage);
    } else if (widget.book.format == BookFormat.md) {
      _scrollController = ScrollController(
        initialScrollOffset: widget.book.lastOffset ?? 0,
      );
    } else if (widget.book.format == BookFormat.epub) {
      _epubChapters = await _loadEpub(widget.book.path);
      _currentPage = widget.book.lastPage ?? 0;
      _pageController = PageController(initialPage: _currentPage);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveProgress() async {
    if (widget.book.format == BookFormat.pdf) {
      final page = _pdfController?.pageListenable.value;
      if (page != null) {
        await _store.updateBookProgress(widget.book.id, lastPage: page);
      }
      return;
    }
    if (widget.book.format == BookFormat.md) {
      await _store.updateBookProgress(
        widget.book.id,
        lastOffset: _scrollController?.offset ?? 0,
      );
      return;
    }
    await _store.updateBookProgress(widget.book.id, lastPage: _currentPage);
  }

  Future<List<_EpubChapter>> _loadEpub(String path) async {
    final bytes = await File(path).readAsBytes();
    final book = await EpubReader.readBook(bytes);
    final chapters = <_EpubChapter>[];
    void visit(List<EpubChapter> items) {
      for (final chapter in items) {
        final title = chapter.Title ?? '未命名章节';
        final html = chapter.HtmlContent ?? '';
        if (html.trim().isNotEmpty) {
          chapters.add(_EpubChapter(title: title, html: html));
        }
        final subs = chapter.SubChapters;
        if (subs != null && subs.isNotEmpty) {
          visit(subs);
        }
      }
    }

    if (book.Chapters != null) {
      visit(book.Chapters!);
    }
    return chapters;
  }

  List<String> _paginateText(String raw, double fontSize) {
    final size = MediaQuery.of(context).size;
    final factor = fontSize * fontSize * 1.4;
    final charsPerPage =
        max(600, min(2400, (size.width * size.height / factor).floor()));
    final pages = <String>[];
    var index = 0;
    while (index < raw.length) {
      final end = min(index + charsPerPage, raw.length);
      pages.add(raw.substring(index, end));
      index = end;
    }
    return pages.isEmpty ? [''] : pages;
  }

  void _openSettings() async {
    if (_settings == null) return;
    final updated = await showModalBottomSheet<ReaderSettings>(
      context: context,
      builder: (context) => _ReaderSettingsSheet(settings: _settings!),
    );
    if (updated == null) return;
    await _settingsStore.save(updated);
    _settings = updated;
    if (widget.book.format == BookFormat.txt) {
      final raw = await File(widget.book.path).readAsString();
      _textPages = _paginateText(raw, updated.fontSize);
      _currentPage = min(_currentPage, _textPages.length - 1);
      _pageController?.jumpToPage(_currentPage);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _openToc() {
    if (_epubChapters.isEmpty) return;
    showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          itemCount: _epubChapters.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(_epubChapters[index].title),
            onTap: () => Navigator.pop(context, index),
          ),
        ),
      ),
    ).then((index) {
      if (index == null) return;
      setState(() => _currentPage = index);
      _pageController?.jumpToPage(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final background = SettingsStore.backgroundFor(settings.theme);
    final foreground = SettingsStore.textFor(settings.theme);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          if (widget.book.format == BookFormat.epub)
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
      ),
      body: _buildContent(settings, foreground),
    );
  }

  Widget _buildContent(ReaderSettings settings, Color foreground) {
    switch (widget.book.format) {
      case BookFormat.pdf:
        final controller = _pdfController;
        if (controller == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return PdfViewPinch(
          controller: controller,
          onPageChanged: (page) => _currentPage = max(0, page - 1),
        );
      case BookFormat.epub:
        if (_epubChapters.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return PageView.builder(
          controller: _pageController,
          onPageChanged: (index) => _currentPage = index,
          itemCount: _epubChapters.length,
          itemBuilder: (context, index) {
            final chapter = _epubChapters[index];
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Html(
                data: chapter.html,
                style: {
                  'body': Style(
                    fontSize: FontSize(settings.fontSize),
                    color: foreground,
                    backgroundColor:
                        SettingsStore.backgroundFor(settings.theme),
                  ),
                  'p': Style(
                    lineHeight: const LineHeight(1.6),
                  ),
                },
              ),
            );
          },
        );
      case BookFormat.md:
        final controller = _scrollController ?? ScrollController();
        _scrollController = controller;
        return Markdown(
          data: File(widget.book.path).readAsStringSync(),
          controller: controller,
          padding: const EdgeInsets.all(16),
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              fontSize: settings.fontSize,
              color: foreground,
              height: 1.6,
            ),
          ),
        );
      case BookFormat.txt:
        if (_textPages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return PageView.builder(
          controller: _pageController,
          onPageChanged: (index) => _currentPage = index,
          itemCount: _textPages.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _textPages[index],
              style: TextStyle(
                fontSize: settings.fontSize,
                color: foreground,
                height: 1.6,
              ),
            ),
          ),
        );
    }
  }
}

class _EpubChapter {
  const _EpubChapter({required this.title, required this.html});

  final String title;
  final String html;
}

class _ReaderSettingsSheet extends StatefulWidget {
  const _ReaderSettingsSheet({required this.settings});

  final ReaderSettings settings;

  @override
  State<_ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<_ReaderSettingsSheet> {
  late double _fontSize;
  late ReaderTheme _theme;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.settings.fontSize;
    _theme = widget.settings.theme;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '阅读设置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text('字号 ${_fontSize.toStringAsFixed(0)}'),
            Slider(
              value: _fontSize,
              min: 14,
              max: 28,
              divisions: 14,
              label: _fontSize.toStringAsFixed(0),
              onChanged: (value) => setState(() => _fontSize = value),
            ),
            const SizedBox(height: 8),
            const Text('背景'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ReaderTheme.values.map((theme) {
                final selected = _theme == theme;
                return ChoiceChip(
                  label: Text(theme.name),
                  selected: selected,
                  onSelected: (_) => setState(() => _theme = theme),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      ReaderSettings(fontSize: _fontSize, theme: _theme),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
