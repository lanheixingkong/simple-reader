import 'dart:typed_data';
import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path/path.dart' as p;

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
      final bookRef = await EpubReader.openBook(await _readFile(path));
      final cover = await bookRef.readCover();
      if (cover != null) {
        return Uint8List.fromList(cover.getBytes());
      }

      final manifestItems = bookRef.Schema?.Package?.Manifest?.Items ?? [];
      final coverByProperty = manifestItems.firstWhere(
        (item) =>
            (item.Properties ?? '').toLowerCase().contains('cover-image'),
        orElse: () => EpubManifestItem(),
      );
      final fromProperty =
          await _imageBytesFromHref(bookRef, coverByProperty.Href);
      if (fromProperty != null) return fromProperty;

      final guideItems = bookRef.Schema?.Package?.Guide?.Items ?? [];
      final guideCover = guideItems.firstWhere(
        (item) {
          final type = (item.Type ?? '').toLowerCase();
          final title = (item.Title ?? '').toLowerCase();
          return type.contains('cover') || title.contains('cover');
        },
        orElse: () => EpubGuideReference(),
      );
      final fromGuideImage = await _imageBytesFromHref(bookRef, guideCover.Href);
      if (fromGuideImage != null) return fromGuideImage;
      final fromGuideHtml =
          await _imageFromHtmlHref(bookRef, guideCover.Href);
      if (fromGuideHtml != null) return fromGuideHtml;

      final coverByName = manifestItems.firstWhere(
        (item) {
          final media = (item.MediaType ?? '').toLowerCase();
          final key = '${item.Id ?? ''} ${item.Href ?? ''}'.toLowerCase();
          return media.startsWith('image/') && key.contains('cover');
        },
        orElse: () => EpubManifestItem(),
      );
      final fromName = await _imageBytesFromHref(bookRef, coverByName.Href);
      if (fromName != null) return fromName;

      final images = bookRef.Content?.Images ?? {};
      dynamic coverRef;
      for (final entry in images.entries) {
        if (entry.key.toLowerCase().contains('cover')) {
          coverRef = entry.value;
          break;
        }
      }
      if (coverRef != null) {
        final bytes = await coverRef.readContentAsBytes();
        return Uint8List.fromList(bytes);
      }

      Uint8List? largest;
      for (final entry in images.entries) {
        final bytes = await entry.value.readContentAsBytes();
        if (largest == null || bytes.length > largest.length) {
          largest = Uint8List.fromList(bytes);
        }
      }
      return largest;
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

  Future<Uint8List?> _imageBytesFromHref(
      EpubBookRef bookRef, String? href) async {
    if (href == null || href.isEmpty) return null;
    final images = bookRef.Content?.Images ?? {};
    dynamic ref = images[href];
    if (ref == null) {
      final normalized = href.replaceFirst(RegExp(r'^\./'), '');
      ref = images[normalized];
      if (ref == null) {
        for (final entry in images.entries) {
          if (entry.key.endsWith(normalized)) {
            ref = entry.value;
            break;
          }
        }
      }
    }
    if (ref == null) return null;
    final bytes = await ref.readContentAsBytes();
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List?> _imageFromHtmlHref(
      EpubBookRef bookRef, String? href) async {
    if (href == null || href.isEmpty) return null;
    final html = await _readHtmlFromHref(bookRef, href);
    if (html == null || html.isEmpty) return null;
    final match =
        RegExp(r'''<img[^>]+src=['"]([^'"]+)''').firstMatch(html);
    if (match == null) return null;
    var src = match.group(1) ?? '';
    if (src.isEmpty || src.startsWith('http')) return null;
    src = src.split('#').first;
    final base = p.dirname(href);
    final resolved = p.normalize(p.join(base, src));
    return _imageBytesFromHref(bookRef, resolved);
  }

  Future<String?> _readHtmlFromHref(
      EpubBookRef bookRef, String href) async {
    final htmlMap = bookRef.Content?.Html ?? {};
    final normalized = href.replaceFirst(RegExp(r'^\./'), '');
    final ref = htmlMap[href] ?? htmlMap[normalized];
    if (ref != null) {
      return ref.readContentAsText();
    }
    for (final entry in htmlMap.entries) {
      if (entry.key.endsWith(normalized)) {
        return entry.value.readContentAsText();
      }
    }
    return null;
  }

  static Color placeholderColor(String seed) {
    final hash = seed.codeUnits.fold<int>(0, (p, c) => p + c);
    final hue = hash % 360;
    return HSLColor.fromAHSL(1, hue.toDouble(), 0.28, 0.85).toColor();
  }
}
