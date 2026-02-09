import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/library.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import 'reader_layout.dart';
import 'reader_settings_sheet.dart';
import 'reader_tap_zones.dart';

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
  PdfController? _controller;
  Timer? _saveTimer;
  final ValueNotifier<bool> _showChrome = ValueNotifier<bool>(false);

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
    _showChrome.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    _settings = settings;
    _controller = PdfController(
      document: PdfDocument.openFile(widget.book.path),
      initialPage: (widget.book.lastPage ?? 1).clamp(1, 999999),
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
        child: controller == null
            ? const Center(child: CircularProgressIndicator())
            : PdfView(
                controller: controller,
                physics: const NeverScrollableScrollPhysics(),
              ),
      ),
    );
  }

  void _toggleChrome() {
    _showChrome.value = !_showChrome.value;
  }

  void _previousPage() {
    final controller = _controller;
    if (controller == null) return;
    final current = controller.pageListenable.value;
    if (current <= 1) return;
    controller.previousPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _nextPage() {
    final controller = _controller;
    if (controller == null) return;
    final current = controller.pageListenable.value;
    final total = controller.pagesCount ?? 0;
    if (current >= total) return;
    controller.nextPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _shareCurrentPage() async {
    final controller = _controller;
    if (controller == null) return;
    final pageNumber = controller.pageListenable.value;
    if (pageNumber == null) return;
    try {
      final document = await controller.document;
      final page = await document.getPage(pageNumber);
      final targetWidth = 1080.0;
      final targetHeight = page.height / page.width * targetWidth;
      final image = await page.render(
        width: targetWidth,
        height: targetHeight,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
        quality: 100,
      );
      await page.close();
      if (image == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(
          dir.path,
          'reader-share-pdf-${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      );
      await file.writeAsBytes(image.bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: widget.book.title,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生成分享图片失败')),
      );
    }
  }
}
