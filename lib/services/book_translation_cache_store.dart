import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'ai_chat_api_store.dart';
import 'app_storage.dart';

class BookTranslationCacheStore {
  BookTranslationCacheStore._();

  static final BookTranslationCacheStore instance =
      BookTranslationCacheStore._();

  Future<Map<String, String>> load({
    required String bookId,
    required AiChatApiSettings settings,
  }) async {
    final file = await _fileFor(bookId: bookId, settings: settings);
    if (!await file.exists()) return const {};
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      final entries = decoded['entries'];
      if (entries is! Map<String, dynamic>) return const {};
      return entries.map(
        (key, value) => MapEntry(key, (value ?? '').toString()),
      );
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveAll({
    required String bookId,
    required AiChatApiSettings settings,
    required Map<String, String> entries,
  }) async {
    final file = await _fileFor(bookId: bookId, settings: settings);
    final payload = {
      'version': 1,
      'provider': settings.provider.name,
      'baseUrl': settings.effectiveBaseUrl(),
      'model': settings.effectiveModel(),
      'entries': entries,
    };
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload));
  }

  static String paragraphKey(String text) {
    return sha1.convert(utf8.encode(text.trim())).toString();
  }

  Future<File> _fileFor({
    required String bookId,
    required AiChatApiSettings settings,
  }) async {
    final dir = await AppStorage.instance.rootDir();
    final safeBookId = bookId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final key = _cacheKey(settings);
    final filename = 'translation-$safeBookId-$key.json';
    return File(p.join(dir.path, 'TranslationCache', filename));
  }

  String _cacheKey(AiChatApiSettings settings) {
    final raw = [
      settings.provider.name,
      settings.effectiveBaseUrl(),
      settings.effectiveModel(),
    ].join('|');
    return sha1.convert(utf8.encode(raw)).toString().substring(0, 12);
  }
}
