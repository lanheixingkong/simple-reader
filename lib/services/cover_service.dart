import 'dart:typed_data';
import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../models/library.dart';

class CoverService {
  CoverService._();

  static final CoverService instance = CoverService._();

  final Map<String, Future<Uint8List?>> _cache = {};

  Future<Uint8List?> loadCover(Book book) {
    return _cache.putIfAbsent(book.id, () async {
      switch (book.format) {
        case BookFormat.epub:
          return _loadEpubCover(book.path);
        case BookFormat.pdf:
          return _renderPdfCover(book.path);
        case BookFormat.txt:
        case BookFormat.md:
          return null;
      }
    });
  }

  Future<Uint8List?> _loadEpubCover(String path) async {
    try {
      final book = await EpubReader.readBook(await _readFile(path));
      final image = book.CoverImage;
      return image?.getBytes();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _renderPdfCover(String path) async {
    try {
      final doc = await PdfDocument.openFile(path);
      final page = await doc.getPage(1);
      final pageImage = await page.render(
        width: page.width * 0.7,
        height: page.height * 0.7,
      );
      await page.close();
      await doc.close();
      return pageImage?.bytes;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _readFile(String path) async {
    final data = await File(path).readAsBytes();
    return Uint8List.fromList(data);
  }

  static Color placeholderColor(String seed) {
    final hash = seed.codeUnits.fold<int>(0, (p, c) => p + c);
    final hue = hash % 360;
    return HSLColor.fromAHSL(1, hue.toDouble(), 0.28, 0.85).toColor();
  }
}
