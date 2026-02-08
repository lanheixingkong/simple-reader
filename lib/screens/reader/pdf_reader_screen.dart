import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../models/library.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import 'reader_layout.dart';
import 'reader_settings_sheet.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  final _store = LibraryStore.instance;
  final _settingsStore = SettingsStore.instance;

  ReaderSettings? _settings;
  PdfControllerPinch? _controller;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveProgress();
    _controller?.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    _settings = settings;
    _controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.book.path),
      initialPage: max(1, widget.book.lastPage ?? 1),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveProgress() async {
    final page = _controller?.pageListenable.value;
    if (page != null) {
      await _store.updateBookProgress(widget.book.id, lastPage: page);
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
    final controller = _controller;
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
      child: controller == null
          ? const Center(child: CircularProgressIndicator())
          : PdfViewPinch(
              controller: controller,
            ),
    );
  }
}
