import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/ai_chat_api_store.dart';
import '../../services/book_translation_cache_store.dart';
import '../../services/book_translation_service.dart';
import '../../services/library_store.dart';
import '../../services/persistent_kv_store.dart';
import '../../services/settings_store.dart';
import 'reader_layout.dart';
import 'ai_chat_screen.dart';
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
  static const _translationModeKeyPrefix = 'text_translation_mode_';

  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;
  final _aiApiStore = AiChatApiStore.instance;
  final _translationCacheStore = BookTranslationCacheStore.instance;
  final _translationService = BookTranslationService();

  ReaderSettings? _settings;
  AiChatApiSettings? _translationSettings;
  ScrollController? _scrollController;
  String _content = '';
  List<String> _paragraphs = const [];
  final Map<String, String> _translations = <String, String>{};
  bool _translating = false;
  bool _translationEnabled = false;
  bool _loaded = false;
  Timer? _saveTimer;
  Timer? _progressSaveTimer;
  Timer? _translationSaveTimer;
  bool _progressDirty = false;
  bool _savingProgress = false;
  final ValueNotifier<bool> _showChrome = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _selectionActive = ValueNotifier<bool>(false);
  String _selectedText = '';
  Future<void> _translationQueue = Future<void>.value();

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
    _translationSaveTimer?.cancel();
    unawaited(_persistTranslations());
    _showChrome.dispose();
    _selectionActive.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    final translationSettings = await _loadTranslationSettings();
    final translationEnabled =
        await PersistentKvStore.instance.getBool(
          '$_translationModeKeyPrefix${widget.book.id}',
        ) ??
        false;
    final raw = await File(widget.book.path).readAsString();
    _settings = settings;
    _translationSettings = translationSettings;
    _content = raw;
    _paragraphs = _translationService.splitParagraphs(raw);
    _translations
      ..clear()
      ..addAll(
        await _translationCacheStore.load(
          bookId: widget.book.id,
          settings: translationSettings,
        ),
      );
    _translationEnabled = translationEnabled;
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
    if (_translationEnabled) {
      _enqueueTranslateAll(forceRefresh: false);
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
    _progressDirty = true;
    _scheduleProgressSave();
  }

  void _scheduleProgressSave() {
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
          tooltip: '字体/背景',
        ),
        IconButton(
          onPressed: () => _openAiChat(),
          icon: const Icon(Icons.chat_bubble_outline),
          tooltip: 'AI问答',
        ),
        IconButton(
          onPressed: _translating ? null : _translateCurrentBook,
          icon: _translating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_translationEnabled ? Icons.translate : Icons.g_translate),
          tooltip: _translationEnabled ? '自动翻译已开启' : '开启自动翻译',
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
                        selectableRegionState.contextMenuButtonItems,
                      );
                      final localizedItems = items
                          .map(_localizedMenuItem)
                          .toList();
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
                      localizedItems.add(
                        ContextMenuButtonItem(
                          label: 'AI问答',
                          onPressed: () {
                            final text = _selectedText;
                            selectableRegionState.hideToolbar();
                            _openAiChat(quote: text);
                          },
                        ),
                      );
                      return AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: selectableRegionState.contextMenuAnchors,
                        buttonItems: localizedItems,
                      );
                    },
                    child: _buildContent(settings, foreground),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildContent(ReaderSettings settings, Color foreground) {
    final style = TextStyle(
      fontSize: settings.fontSize,
      color: foreground,
      height: 1.6,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final paragraph in _paragraphs)
          _buildTranslatedParagraph(paragraph, style),
      ],
    );
  }

  Widget _buildTranslatedParagraph(String text, TextStyle style) {
    final translation = _translations[_translationService.paragraphKey(text)];
    final hasTranslation =
        translation != null &&
        translation.trim().isNotEmpty &&
        translation.trim() != text.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: style),
          if (hasTranslation)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                translation.trim(),
                style: style.copyWith(
                  fontSize: style.fontSize != null
                      ? style.fontSize! * 0.96
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _translateCurrentBook() async {
    if (_paragraphs.isEmpty) {
      _showSnack('当前内容没有可翻译的文字');
      return;
    }
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
      await _translateMissingParagraphs(
        forceRefresh: true,
        notifyIfChinese: true,
      );
    } catch (error) {
      _showSnack('翻译失败：$error');
    }
    _enqueueTranslateAll(forceRefresh: false);
  }

  void _enqueueTranslateAll({required bool forceRefresh}) {
    _translationQueue = _translationQueue.then(
      (_) => _translateMissingParagraphs(
        forceRefresh: forceRefresh,
        notifyIfChinese: false,
      ),
    );
  }

  Future<void> _translateMissingParagraphs({
    required bool forceRefresh,
    required bool notifyIfChinese,
  }) async {
    final hasNonChinese = _paragraphs.any(
      (item) => !_translationService.isLikelyChinese(item),
    );
    if (!hasNonChinese) {
      if (notifyIfChinese) {
        _showSnack('当前内容已是中文，不需要翻译');
      }
      return;
    }
    final settings = await _loadTranslationSettings(refresh: forceRefresh);
    final missing = _paragraphs.where((item) {
      if (_translationService.isLikelyChinese(item)) return false;
      return !_translations.containsKey(_translationService.paragraphKey(item));
    }).toList();
    if (missing.isEmpty) {
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (mounted) {
      setState(() {
        _translating = true;
      });
    } else {
      _translating = true;
    }
    try {
      final translated = await _translationService.translateParagraphs(
        settings: settings,
        paragraphs: missing,
      );
      if (translated.isEmpty) return;
      _translations.addAll(translated);
      _schedulePersistTranslations();
      if (mounted) {
        setState(() {});
      }
    } finally {
      if (mounted) {
        setState(() {
          _translating = false;
        });
      } else {
        _translating = false;
      }
    }
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _openShareSheet(
    String text, {
    required String sourceLabel,
  }) async {
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
