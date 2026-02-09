import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import 'reader_layout.dart';
import 'reader_share_sheet.dart';
import 'reader_settings_sheet.dart';
import 'reader_tap_zones.dart';

class TextReaderScreen extends StatefulWidget {
  const TextReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends State<TextReaderScreen> {
  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;

  ReaderSettings? _settings;
  List<String> _pages = [];
  PageController? _pageController;
  int _currentPage = 0;
  Timer? _saveTimer;
  final ValueNotifier<bool> _showChrome = ValueNotifier<bool>(false);
  String _selectedText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    _pageController?.dispose();
    _saveTimer?.cancel();
    _showChrome.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    final raw = await File(widget.book.path).readAsString();
    _settings = settings;
    _pages = _paginateText(raw, settings.fontSize);
    _currentPage = min(widget.book.lastPage ?? 0, max(0, _pages.length - 1));
    _pageController = PageController(initialPage: _currentPage);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveProgress() async {
    await _store.updateBookProgress(widget.book.id, lastPage: _currentPage);
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
    final raw = await File(widget.book.path).readAsString();
    _pages = _paginateText(raw, updated.fontSize);
    _currentPage = min(_currentPage, _pages.length - 1);
    _pageController?.jumpToPage(_currentPage);
    if (mounted) {
      setState(() => _settings = updated);
    }
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
    return ReaderLayout(
      book: widget.book,
      settings: settings,
      showAppBarListenable: _showChrome,
      actions: [
        IconButton(
          onPressed: _shareCurrentPage,
          icon: const Icon(Icons.ios_share),
          tooltip: '分享',
        ),
      ],
      bottomActions: [
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
        child: _pages.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => _currentPage = index,
                itemCount: _pages.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectionArea(
                    onSelectionChanged: (content) {
                      _selectedText = content?.plainText.trim() ?? '';
                    },
                    contextMenuBuilder: (context, selectableRegionState) {
                      final items = List<ContextMenuButtonItem>.from(
                        selectableRegionState.contextMenuButtonItems ??
                            const [],
                      );
                      final localizedItems =
                          items.map(_localizedMenuItem).toList();
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
                    child: Text(
                      _pages[index],
                      style: TextStyle(
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

  void _previousPage() {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    if (_currentPage <= 0) return;
    controller.previousPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _nextPage() {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    if (_currentPage >= _pages.length - 1) return;
    controller.nextPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _shareCurrentPage() async {
    if (_pages.isEmpty) return;
    final text = _pages[_currentPage].trim();
    if (text.isEmpty) return;
    await _openShareSheet(text, sourceLabel: '当前屏幕');
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
}
