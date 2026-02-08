import 'package:flutter/material.dart';

import '../models/library.dart';
import 'reader/epub_reader_screen.dart';
import 'reader/markdown_reader_screen.dart';
import 'reader/pdf_reader_screen.dart';
import 'reader/text_reader_screen.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    switch (book.format) {
      case BookFormat.epub:
        return EpubReaderScreen(book: book);
      case BookFormat.pdf:
        return PdfReaderScreen(book: book);
      case BookFormat.md:
        return MarkdownReaderScreen(book: book);
      case BookFormat.txt:
        return TextReaderScreen(book: book);
    }
  }
}
