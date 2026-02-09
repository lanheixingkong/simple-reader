import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../models/library.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import 'reader_layout.dart';
import 'reader_share_sheet.dart';
import 'reader_settings_sheet.dart';
import 'reader_tap_zones.dart';

class MarkdownReaderScreen extends StatefulWidget {
  const MarkdownReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<MarkdownReaderScreen> createState() => _MarkdownReaderScreenState();
}

class _MarkdownReaderScreenState extends State<MarkdownReaderScreen>
    with WidgetsBindingObserver {
  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;

  ReaderSettings? _settings;
  ScrollController? _scrollController;
  String _content = '';
  String _plainText = '';
  Timer? _saveTimer;
  Timer? _progressSaveTimer;
  final ValueNotifier<bool> _showChrome = ValueNotifier<bool>(false);
  final List<_TocEntry> _toc = [];
  final List<GlobalKey> _headingKeys = [];
  int _headingKeyCursor = 0;
  String _selectedText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    _scrollController?.dispose();
    _saveTimer?.cancel();
    _progressSaveTimer?.cancel();
    _showChrome.dispose();
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
    _settings = settings;
    _content = await File(widget.book.path).readAsString();
    _plainText = _markdownToPlainText(_content);
    _buildToc(_content);
    _scrollController = ScrollController(
      initialScrollOffset: widget.book.lastOffset ?? 0,
    );
    _scrollController?.addListener(_onScroll);
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final controller = _scrollController;
        if (controller == null || !controller.hasClients) return;
        final max = controller.position.maxScrollExtent;
        final raw = widget.book.lastOffset ?? 0.0;
        final target = raw.clamp(0.0, max);
        if (target != controller.offset) {
          controller.jumpTo(target);
        }
      });
    }
  }

  Future<void> _saveProgress() async {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) {
      return;
    }
    await _store.updateBookProgress(
      widget.book.id,
      lastOffset: controller.offset,
    );
  }

  void _onScroll() {
    _scheduleProgressSave();
  }

  void _scheduleProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(
      const Duration(milliseconds: 500),
      _saveProgress,
    );
  }

  void _buildToc(String content) {
    _toc.clear();
    _headingKeys.clear();
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    final lines = const LineSplitter().convert(content);
    final nodes = document.parseLines(lines);
    void visit(md.Node node) {
      if (node is md.Element) {
        final tag = node.tag;
        if (tag.length == 2 && tag.startsWith('h')) {
          final level = int.tryParse(tag.substring(1));
          if (level != null && level >= 1 && level <= 6) {
            final title = node.textContent.trim();
            if (title.isNotEmpty) {
              _toc.add(_TocEntry(title: title, level: level));
              _headingKeys.add(GlobalKey());
            }
          }
        }
        final children = node.children;
        if (children != null) {
          for (final child in children) {
            visit(child);
          }
        }
      }
    }
    for (final node in nodes) {
      visit(node);
    }
  }

  GlobalKey? _nextHeadingKey() {
    if (_headingKeyCursor >= _headingKeys.length) return null;
    return _headingKeys[_headingKeyCursor++];
  }

  void _openToc() {
    if (_toc.isEmpty) return;
    showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          itemCount: _toc.length,
          itemBuilder: (context, index) {
            final entry = _toc[index];
            return ListTile(
              title: Padding(
                padding: EdgeInsets.only(left: (entry.level - 1) * 12.0),
                child: Text(entry.title),
              ),
              onTap: () => Navigator.pop(context, index),
            );
          },
        ),
      ),
    ).then((index) {
      if (index == null) return;
      _scrollToHeading(index);
    });
  }

  void _scrollToHeading(int index) {
    if (index < 0 || index >= _headingKeys.length) return;
    final key = _headingKeys[index];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = key.currentContext;
      final controller = _scrollController;
      if (context == null || controller == null || !controller.hasClients) {
        return;
      }
      final renderObject = context.findRenderObject();
      if (renderObject == null) return;
      final viewport = RenderAbstractViewport.of(renderObject);
      if (viewport == null) return;
      final target = viewport.getOffsetToReveal(renderObject, 0.1).offset;
      final max = controller.position.maxScrollExtent;
      controller.animateTo(
        target.clamp(0.0, max),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
      );
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final foreground = SettingsStore.textFor(settings.theme);
    _headingKeyCursor = 0;
    return ReaderLayout(
      book: widget.book,
      settings: settings,
      showAppBarListenable: _showChrome,
      actions: [
        if (_toc.isNotEmpty)
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
      child: ReaderTapZones(
        onTapLeft: _pageUp,
        onTapRight: _pageDown,
        onTapCenter: _toggleChrome,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: SelectionArea(
            onSelectionChanged: (content) {
              _selectedText = content?.plainText.trim() ?? '';
            },
            contextMenuBuilder: (context, selectableRegionState) {
              final items = List<ContextMenuButtonItem>.from(
                selectableRegionState.contextMenuButtonItems ?? const [],
              );
              final localizedItems = items.map(_localizedMenuItem).toList();
              localizedItems.add(
                ContextMenuButtonItem(
                  label: '分享',
                  onPressed: () {
                    final text = _selectedText;
                    selectableRegionState.hideToolbar();
                    if (text.isEmpty) return;
                    _openShareSheet(text, sourceLabel: '已选文字');
                  },
                ),
              );
              return AdaptiveTextSelectionToolbar.buttonItems(
                anchors: selectableRegionState.contextMenuAnchors,
                buttonItems: localizedItems,
              );
            },
            child: MarkdownBody(
              data: _content,
              builders: {
                'h1': _HeadingBuilder(_nextHeadingKey),
                'h2': _HeadingBuilder(_nextHeadingKey),
                'h3': _HeadingBuilder(_nextHeadingKey),
                'h4': _HeadingBuilder(_nextHeadingKey),
                'h5': _HeadingBuilder(_nextHeadingKey),
                'h6': _HeadingBuilder(_nextHeadingKey),
              },
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  fontSize: settings.fontSize,
                  color: foreground,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleChrome() {
    _showChrome.value = !_showChrome.value;
  }

  void _pageUp() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final height = MediaQuery.of(context).size.height;
    final target = (controller.offset - height * 0.9).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _pageDown() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final height = MediaQuery.of(context).size.height;
    final target = (controller.offset + height * 0.9).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _shareCurrentScreen() async {
    final text = _estimateVisibleText();
    if (text.trim().isEmpty) return;
    await _openShareSheet(text, sourceLabel: '当前屏幕');
  }

  String _estimateVisibleText() {
    if (_plainText.isEmpty) return '';
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) {
      return _plainText;
    }
    final settings = _settings;
    if (settings == null) return _plainText;
    final size = MediaQuery.of(context).size;
    final factor = settings.fontSize * settings.fontSize * 1.4;
    final charsPerScreen = math.max(
      600,
      math.min(2400, (size.width * size.height / factor).floor()),
    );
    final maxExtent = controller.position.maxScrollExtent;
    final progress = maxExtent <= 0
        ? 0.0
        : (controller.offset / maxExtent).clamp(0.0, 1.0);
    final start = (_plainText.length * progress).floor();
    final end = (start + charsPerScreen).clamp(0, _plainText.length);
    return _plainText.substring(start, end);
  }

  Future<void> _openShareSheet(String text,
      {required String sourceLabel}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReaderShareSheet(
        title: widget.book.title,
        author: '未知作者',
        text: text,
        sourceLabel: sourceLabel,
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

  String _markdownToPlainText(String content) {
    var text = content;
    text = text.replaceAll(RegExp(r'`{3}[^`]*`{3}', multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'`([^`]*)`'), r'$1');
    text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^\)]*\)'), ' ');
    text = text.replaceAll(RegExp(r'\[[^\]]*\]\([^\)]*\)'), ' ');
    text = text.replaceAll(RegExp(r'[#>*_\\-]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{2,}'), '\n\n');
    return text.trim();
  }
}

class _TocEntry {
  const _TocEntry({required this.title, required this.level});

  final String title;
  final int level;
}

class _HeadingBuilder extends MarkdownElementBuilder {
  _HeadingBuilder(this._nextKey);

  final GlobalKey? Function() _nextKey;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final key = _nextKey();
    final style = preferredStyle ?? DefaultTextStyle.of(context).style;
    return Container(
      key: key,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        element.textContent,
        style: style,
      ),
    );
  }
}
