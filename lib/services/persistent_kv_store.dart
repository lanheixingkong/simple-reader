import 'dart:async';
import 'dart:convert';

import 'app_storage.dart';

class PersistentKvStore {
  PersistentKvStore._();

  static final PersistentKvStore instance = PersistentKvStore._();

  Map<String, dynamic>? _cache;
  Future<void>? _loadFuture;
  Future<void> _writeQueue = Future<void>.value();

  Future<String?> getString(String key) async {
    final data = await _load();
    return data[key] as String?;
  }

  Future<bool?> getBool(String key) async {
    final data = await _load();
    return data[key] as bool?;
  }

  Future<double?> getDouble(String key) async {
    final data = await _load();
    final value = data[key];
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  Future<int?> getInt(String key) async {
    final data = await _load();
    final value = data[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  Future<void> setString(String key, String value) {
    return _setValue(key, value);
  }

  Future<void> setBool(String key, bool value) {
    return _setValue(key, value);
  }

  Future<void> setDouble(String key, double value) {
    return _setValue(key, value);
  }

  Future<void> setInt(String key, int value) {
    return _setValue(key, value);
  }

  Future<Map<String, dynamic>> _load() async {
    final cache = _cache;
    if (cache != null) {
      return cache;
    }
    _loadFuture ??= _loadFromDisk();
    await _loadFuture;
    return _cache ?? <String, dynamic>{};
  }

  Future<void> _loadFromDisk() async {
    final file = await AppStorage.instance.file('kv_store.json');
    if (!await file.exists()) {
      _cache = <String, dynamic>{};
      return;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _cache = Map<String, dynamic>.from(decoded);
      } else {
        _cache = <String, dynamic>{};
      }
    } catch (_) {
      _cache = <String, dynamic>{};
    }
  }

  Future<void> _setValue(String key, Object value) async {
    await _load();
    _cache![key] = value;
    _writeQueue = _writeQueue.then((_) => _persist());
    return _writeQueue;
  }

  Future<void> _persist() async {
    final file = await AppStorage.instance.file('kv_store.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_cache));
  }
}
