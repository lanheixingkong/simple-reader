import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/library.dart';

class LibraryStore {
  LibraryStore._();

  static final LibraryStore instance = LibraryStore._();

  late Directory _rootDir;
  late Directory _booksDir;
  late File _dataFile;
  bool _initialized = false;

  LibraryState _state = LibraryState.empty();

  LibraryState get state => _state;

  Future<void> init() async {
    if (_initialized) return;
    final docsDir = await getApplicationDocumentsDirectory();
    _rootDir = docsDir;
    _booksDir = Directory(p.join(docsDir.path, 'Books'));
    if (!await _booksDir.exists()) {
      await _booksDir.create(recursive: true);
    }
    _dataFile = File(p.join(docsDir.path, 'library.json'));
    await load();
    await _ensureHashes();
    await importFromInbox();
    _initialized = true;
  }

  Future<void> load() async {
    if (await _dataFile.exists()) {
      final raw = await _dataFile.readAsString();
      _state = LibraryState.fromRawJson(raw);
    } else {
      _state = LibraryState.empty();
    }
  }

  Future<void> save() async {
    await _dataFile.writeAsString(_state.toRawJson());
  }

  Future<void> createFolder(String name) async {
    final folder = Folder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _state.folders.add(folder);
    await save();
  }

  Future<void> deleteFolder(String folderId) async {
    _state.folders.removeWhere((folder) => folder.id == folderId);
    for (final book in _state.books) {
      if (book.folderId == folderId) {
        book.folderId = null;
      }
    }
    await save();
  }

  Future<void> deleteFolderAndBooks(String folderId) async {
    final toDelete =
        _state.books.where((book) => book.folderId == folderId).toList();
    for (final book in toDelete) {
      final file = File(book.path);
      if (await file.exists()) {
        await file.delete();
      }
      _state.books.remove(book);
    }
    _state.folders.removeWhere((folder) => folder.id == folderId);
    await save();
  }

  Future<void> moveBook(String bookId, String? folderId) async {
    final book = _state.books.firstWhere((book) => book.id == bookId);
    book.folderId = folderId;
    await save();
  }

  Future<void> updateBookProgress(String bookId,
      {int? lastPage, double? lastOffset, double? lastProgress}) async {
    final book = _state.books.firstWhere((book) => book.id == bookId);
    if (lastPage != null) {
      book.lastPage = lastPage;
    }
    if (lastOffset != null) {
      book.lastOffset = lastOffset;
    }
    if (lastProgress != null) {
      book.lastProgress = lastProgress;
    }
    await save();
  }

  Future<void> deleteBook(String bookId) async {
    final index = _state.books.indexWhere((book) => book.id == bookId);
    if (index == -1) return;
    final book = _state.books.removeAt(index);
    final file = File(book.path);
    if (await file.exists()) {
      await file.delete();
    }
    await save();
  }

  Future<void> _ensureHashes() async {
    var changed = false;
    for (final book in _state.books) {
      if (book.hash != null) continue;
      final file = File(book.path);
      if (!await file.exists()) continue;
      book.hash = await _hashFile(file);
      changed = true;
    }
    if (changed) {
      await save();
    }
  }

  Future<List<Book>> importFiles(List<String> filePaths,
      {String? folderId}) async {
    final imported = <Book>[];
    final existingHashes = _state.books
        .map((book) => book.hash)
        .whereType<String>()
        .toSet();
    for (final path in filePaths) {
      final format = BookFormatX.fromPath(path);
      if (format == null) continue;
      final sourceFile = File(path);
      if (!await sourceFile.exists()) continue;
      final fileHash = await _hashFile(sourceFile);
      if (existingHashes.contains(fileHash)) {
        continue;
      }
      final baseName = p.basename(path);
      final targetName = '${DateTime.now().millisecondsSinceEpoch}_$baseName';
      final targetPath = p.join(_booksDir.path, targetName);
      await sourceFile.copy(targetPath);
      final book = Book(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: p.basenameWithoutExtension(baseName),
        path: targetPath,
        format: format,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        folderId: folderId,
        hash: fileHash,
      );
      _state.books.add(book);
      existingHashes.add(fileHash);
      imported.add(book);
    }
    if (imported.isNotEmpty) {
      await save();
    }
    return imported;
  }

  Future<List<Book>> importFromInbox() async {
    final inboxDir = Directory(p.join(_rootDir.path, 'Inbox'));
    if (!await inboxDir.exists()) {
      return [];
    }
    final files =
        inboxDir.listSync().whereType<File>().map((file) => file.path).toList();
    if (files.isEmpty) return [];
    final imported = await importFiles(files);
    for (final path in files) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    return imported;
  }

  Future<List<Book>> refreshInbox() async {
    final imported = await importFromInbox();
    if (imported.isNotEmpty) {
      await save();
    }
    return imported;
  }

  Future<String> _hashFile(File file) async {
    final digest = await sha1.bind(file.openRead()).first;
    return digest.toString();
  }
}
