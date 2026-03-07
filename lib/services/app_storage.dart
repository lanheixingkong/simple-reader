import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppStorage {
  AppStorage._();

  static final AppStorage instance = AppStorage._();
  static const MethodChannel _channel = MethodChannel('simple_reader/storage');

  Directory? _rootDir;
  Future<Directory>? _initFuture;

  Future<Directory> rootDir() {
    final existing = _rootDir;
    if (existing != null) {
      return Future<Directory>.value(existing);
    }
    return _initFuture ??= _init();
  }

  Future<File> file(String name) async {
    final root = await rootDir();
    return File(p.join(root.path, name));
  }

  Future<Directory> directory(String name) async {
    final root = await rootDir();
    final dir = Directory(p.join(root.path, name));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _init() async {
    final localDocsDir = await getApplicationDocumentsDirectory();
    var chosenRoot = localDocsDir;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final iCloudRoot = await _resolveICloudRoot();
      if (iCloudRoot != null) {
        await _migrateLegacyData(localDocsDir, iCloudRoot);
        chosenRoot = iCloudRoot;
      }
    }
    if (!await chosenRoot.exists()) {
      await chosenRoot.create(recursive: true);
    }
    _rootDir = chosenRoot;
    return chosenRoot;
  }

  Future<Directory?> _resolveICloudRoot() async {
    try {
      final containerPath = await _channel.invokeMethod<String>(
        'getICloudContainerPath',
      );
      if (containerPath == null || containerPath.trim().isEmpty) {
        return null;
      }
      final root = Directory(
        p.join(containerPath, 'Documents', 'SimpleReaderLibrary'),
      );
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      return root;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _migrateLegacyData(
    Directory localDocsDir,
    Directory iCloudRoot,
  ) async {
    final localLibrary = File(p.join(localDocsDir.path, 'library.json'));
    final cloudLibrary = File(p.join(iCloudRoot.path, 'library.json'));
    final localBooks = Directory(p.join(localDocsDir.path, 'Books'));
    final cloudBooks = Directory(p.join(iCloudRoot.path, 'Books'));
    final localCache = Directory(p.join(localDocsDir.path, 'PdfTextCache'));
    final cloudCache = Directory(p.join(iCloudRoot.path, 'PdfTextCache'));
    final localKv = File(p.join(localDocsDir.path, 'kv_store.json'));
    final cloudKv = File(p.join(iCloudRoot.path, 'kv_store.json'));

    final hasCloudLibrary =
        await cloudLibrary.exists() || await cloudBooks.exists();
    if (!hasCloudLibrary) {
      if (await localLibrary.exists()) {
        await cloudLibrary.parent.create(recursive: true);
        await localLibrary.copy(cloudLibrary.path);
      }
      if (await localBooks.exists()) {
        await _copyDirectory(localBooks, cloudBooks);
      }
      if (await localCache.exists()) {
        await _copyDirectory(localCache, cloudCache);
      }
    }

    if (!await cloudKv.exists() && await localKv.exists()) {
      await cloudKv.parent.create(recursive: true);
      await localKv.copy(cloudKv.path);
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }
    await for (final entity in source.list(recursive: false)) {
      final targetPath = p.join(destination.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      }
    }
  }
}
