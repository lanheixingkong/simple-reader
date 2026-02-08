import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/library.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import 'reader_layout.dart';
import 'reader_settings_sheet.dart';

class MarkdownReaderScreen extends StatefulWidget {
  const MarkdownReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<MarkdownReaderScreen> createState() => _MarkdownReaderScreenState();
}

class _MarkdownReaderScreenState extends State<MarkdownReaderScreen> {
  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;

  ReaderSettings? _settings;
  ScrollController? _scrollController;
  String _content = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    _scrollController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    _settings = settings;
    _content = await File(widget.book.path).readAsString();
    _scrollController = ScrollController(
      initialScrollOffset: widget.book.lastOffset ?? 0,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveProgress() async {
    await _store.updateBookProgress(
      widget.book.id,
      lastOffset: _scrollController?.offset ?? 0,
    );
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
    setState(() => _settings = updated);
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
      actions: [
        IconButton(
          onPressed: _openSettings,
          icon: const Icon(Icons.text_fields),
          tooltip: '阅读设置',
        ),
      ],
      child: Markdown(
        data: _content,
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
            fontSize: settings.fontSize,
            color: foreground,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}
