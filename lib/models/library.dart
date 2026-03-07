import 'dart:convert';

import 'package:path/path.dart' as p;

enum BookFormat { epub, pdf, txt, md }

extension BookFormatX on BookFormat {
  String get extensionLabel {
    switch (this) {
      case BookFormat.epub:
        return 'epub';
      case BookFormat.pdf:
        return 'pdf';
      case BookFormat.txt:
        return 'txt';
      case BookFormat.md:
        return 'md';
    }
  }

  static BookFormat? fromPath(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.epub':
        return BookFormat.epub;
      case '.pdf':
        return BookFormat.pdf;
      case '.txt':
        return BookFormat.txt;
      case '.md':
      case '.markdown':
        return BookFormat.md;
    }
    return null;
  }
}

class Book {
  Book({
    required this.id,
    required this.title,
    required this.path,
    required this.format,
    required this.addedAt,
    this.folderId,
    this.lastPage,
    this.lastOffset,
    this.lastProgress,
    this.hash,
  });

  final String id;
  final String title;
  String path;
  final BookFormat format;
  final int addedAt;
  String? folderId;
  int? lastPage;
  double? lastOffset;
  double? lastProgress;
  String? hash;

  Map<String, dynamic> toJson({String? pathOverride}) => {
    'id': id,
    'title': title,
    'path': pathOverride ?? path,
    'format': format.extensionLabel,
    'addedAt': addedAt,
    'folderId': folderId,
    'lastPage': lastPage,
    'lastOffset': lastOffset,
    'lastProgress': lastProgress,
    'hash': hash,
  };

  static Book fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String,
    title: json['title'] as String,
    path: json['path'] as String,
    format: BookFormat.values.firstWhere(
      (format) => format.extensionLabel == json['format'],
      orElse: () => BookFormat.txt,
    ),
    addedAt: json['addedAt'] as int,
    folderId: json['folderId'] as String?,
    lastPage: json['lastPage'] as int?,
    lastOffset: (json['lastOffset'] as num?)?.toDouble(),
    lastProgress: (json['lastProgress'] as num?)?.toDouble(),
    hash: json['hash'] as String?,
  );
}

class Folder {
  Folder({required this.id, required this.name, required this.createdAt});

  final String id;
  final String name;
  final int createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
  };

  static Folder fromJson(Map<String, dynamic> json) => Folder(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: json['createdAt'] as int,
  );
}

class LibraryState {
  LibraryState({required this.books, required this.folders});

  final List<Book> books;
  final List<Folder> folders;

  factory LibraryState.empty() => LibraryState(books: [], folders: []);

  Map<String, dynamic> toJson({String Function(Book book)? pathResolver}) => {
    'books': books
        .map(
          (book) => book.toJson(
            pathOverride: pathResolver == null ? null : pathResolver(book),
          ),
        )
        .toList(),
    'folders': folders.map((folder) => folder.toJson()).toList(),
  };

  String toRawJson({String Function(Book book)? pathResolver}) =>
      jsonEncode(toJson(pathResolver: pathResolver));

  static LibraryState? tryFromRawJson(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return LibraryState.empty();
    }
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is! Map) {
        return null;
      }
      final json = Map<String, dynamic>.from(decoded);
      final booksRaw = json['books'];
      final foldersRaw = json['folders'];
      final books = booksRaw is List
          ? booksRaw
                .whereType<Map>()
                .map((item) => Book.fromJson(Map<String, dynamic>.from(item)))
                .toList()
          : <Book>[];
      final folders = foldersRaw is List
          ? foldersRaw
                .whereType<Map>()
                .map((item) => Folder.fromJson(Map<String, dynamic>.from(item)))
                .toList()
          : <Folder>[];
      return LibraryState(books: books, folders: folders);
    } catch (_) {
      return null;
    }
  }

  factory LibraryState.fromRawJson(String raw) {
    return tryFromRawJson(raw) ?? LibraryState.empty();
  }
}
