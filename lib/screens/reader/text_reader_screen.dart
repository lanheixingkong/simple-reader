import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import 'reader_layout.dart';
import 'reader_settings_sheet.dart';

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
  bool _showChrome = false;

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
      showAppBar: _showChrome,
      actions: [
        IconButton(
          onPressed: _openSettings,
          icon: const Icon(Icons.text_fields),
          tooltip: '阅读设置',
        ),
      ],
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(() => _showChrome = !_showChrome),
        child: _pages.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => _currentPage = index,
                itemCount: _pages.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.all(16),
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
    );
  }
}
