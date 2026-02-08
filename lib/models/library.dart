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
  final String path;
  final BookFormat format;
  final int addedAt;
  String? folderId;
  int? lastPage;
  double? lastOffset;
  double? lastProgress;
  String? hash;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'path': path,
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
  Folder({
    required this.id,
    required this.name,
    required this.createdAt,
  });

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
  LibraryState({
    required this.books,
    required this.folders,
  });

  final List<Book> books;
  final List<Folder> folders;

  factory LibraryState.empty() => LibraryState(books: [], folders: []);

  Map<String, dynamic> toJson() => {
        'books': books.map((book) => book.toJson()).toList(),
        'folders': folders.map((folder) => folder.toJson()).toList(),
      };

  String toRawJson() => jsonEncode(toJson());

  factory LibraryState.fromRawJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final books = (json['books'] as List<dynamic>? ?? [])
        .map((item) => Book.fromJson(item as Map<String, dynamic>))
        .toList();
    final folders = (json['folders'] as List<dynamic>? ?? [])
        .map((item) => Folder.fromJson(item as Map<String, dynamic>))
        .toList();
    return LibraryState(books: books, folders: folders);
  }
}
