import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import 'reader_layout.dart';
import 'reader_selection_auto_scroll.dart';
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
  ScrollController? _scrollController;
  String _content = '';
  bool _loaded = false;
  Timer? _saveTimer;
  Timer? _progressSaveTimer;
  final ValueNotifier<bool> _showChrome = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _selectionActive = ValueNotifier<bool>(false);
  String _selectedText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    _scrollController?.dispose();
    _saveTimer?.cancel();
    _progressSaveTimer?.cancel();
    _showChrome.dispose();
    _selectionActive.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    final raw = await File(widget.book.path).readAsString();
    _settings = settings;
    _content = raw;
    _loaded = true;
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
        final rawOffset = widget.book.lastOffset ?? 0.0;
        final target = rawOffset.clamp(0.0, max);
        if (target != controller.offset) {
          controller.jumpTo(target);
        }
      });
    }
  }

  Future<void> _saveProgress() async {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
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
    if (mounted) {
      setState(() => _settings = updated);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = _scrollController;
        if (controller == null || !controller.hasClients) return;
        final max = controller.position.maxScrollExtent;
        final target = controller.offset.clamp(0.0, max);
        if (target != controller.offset) {
          controller.jumpTo(target);
        }
      });
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
        onTapLeft: _pageUp,
        onTapRight: _pageDown,
        onTapCenter: _toggleChrome,
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ReaderSelectionAutoScroll(
                controller: _scrollController,
                selectionActive: _selectionActive,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: SelectionArea(
                    onSelectionChanged: (content) {
                      final text = content?.plainText.trim() ?? '';
                      _selectedText = text;
                      _selectionActive.value = text.isNotEmpty;
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
                      _content,
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

  Future<void> _shareCurrentPage() async {
    final text = _estimateVisibleText().trim();
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

  String _estimateVisibleText() {
    if (_content.isEmpty) return '';
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) {
      return _content;
    }
    final settings = _settings;
    if (settings == null) return _content;
    final size = MediaQuery.of(context).size;
    final factor = settings.fontSize * settings.fontSize * 1.4;
    final charsPerScreen = max(
      600,
      min(2400, (size.width * size.height / factor).floor()),
    );
    final maxExtent = controller.position.maxScrollExtent;
    final progress = maxExtent <= 0
        ? 0.0
        : (controller.offset / maxExtent).clamp(0.0, 1.0);
    final start = (_content.length * progress).floor();
    final end = (start + charsPerScreen).clamp(0, _content.length);
    return _content.substring(start, end);
  }
}
