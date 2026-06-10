import 'dart:async';

import 'package:flutter/material.dart';

import '../models/library.dart';
import '../services/reading_stats_store.dart';
import 'reader/epub_reader_screen.dart';
import 'reader/markdown_reader_screen.dart';
import 'reader/pdf_reader_screen.dart';
import 'reader/text_reader_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final _statsStore = ReadingStatsStore.instance;
  DateTime? _sessionStartedAt;
  Timer? _flushTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumeSession();
    _flushTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _flushSession(continueSession: true),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushTimer?.cancel();
    unawaited(_flushSession());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeSession();
    } else {
      unawaited(_flushSession());
    }
  }

  void _resumeSession() {
    _sessionStartedAt ??= DateTime.now();
  }

  Future<void> _flushSession({bool continueSession = false}) async {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) return;
    final endedAt = DateTime.now();
    _sessionStartedAt = continueSession ? endedAt : null;
    try {
      await _statsStore.addSession(startedAt, endedAt);
    } catch (_) {
      // Reading must remain usable even if statistics persistence fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.book.format) {
      case BookFormat.epub:
        return EpubReaderScreen(book: widget.book);
      case BookFormat.pdf:
        return PdfReaderScreen(book: widget.book);
      case BookFormat.md:
        return MarkdownReaderScreen(book: widget.book);
      case BookFormat.txt:
        return TextReaderScreen(book: widget.book);
    }
  }
}
