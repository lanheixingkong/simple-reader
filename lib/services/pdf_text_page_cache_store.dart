import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'pdf_text_api_store.dart';

class PdfTextCachedPage {
  const PdfTextCachedPage({required this.text, required this.source});

  final String text;
  final String source;

  Map<String, dynamic> toJson() {
    return {'text': text, 'source': source};
  }

  factory PdfTextCachedPage.fromJson(Map<String, dynamic> json) {
    return PdfTextCachedPage(
      text: (json['text'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
    );
  }
}

class PdfTextPageCacheStore {
  PdfTextPageCacheStore._();

  static final PdfTextPageCacheStore instance = PdfTextPageCacheStore._();

  Future<Map<int, PdfTextCachedPage>> load({
    required String bookId,
    required PdfTextApiSettings settings,
  }) async {
    final file = await _fileFor(bookId: bookId, settings: settings);
    if (!await file.exists()) return const {};
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      final pages = decoded['pages'];
      if (pages is! Map<String, dynamic>) return const {};
      final result = <int, PdfTextCachedPage>{};
      for (final entry in pages.entries) {
        final page = int.tryParse(entry.key);
        if (page == null || entry.value is! Map<String, dynamic>) continue;
        result[page] = PdfTextCachedPage.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveAll({
    required String bookId,
    required PdfTextApiSettings settings,
    required Map<int, PdfTextCachedPage> pages,
  }) async {
    final file = await _fileFor(bookId: bookId, settings: settings);
    final payload = {
      'version': 1,
      'provider': settings.provider.name,
      'baseUrl': settings.effectiveBaseUrl(),
      'model': settings.effectiveModel(),
      'pages': {
        for (final entry in pages.entries) '${entry.key}': entry.value.toJson(),
      },
    };
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload));
  }

  Future<File> _fileFor({
    required String bookId,
    required PdfTextApiSettings settings,
  }) async {
    final dir = await AppStorage.instance.rootDir();
    final key = _cacheKey(settings);
    final safeBookId = bookId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final filename = 'pdf-text-$safeBookId-$key.json';
    return File(p.join(dir.path, 'PdfTextCache', filename));
  }

  String _cacheKey(PdfTextApiSettings settings) {
    final raw = [
      settings.provider.name,
      settings.effectiveBaseUrl(),
      settings.effectiveModel(),
      settings.prompt,
    ].join('|');
    return sha1.convert(utf8.encode(raw)).toString().substring(0, 12);
  }
}
