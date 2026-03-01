import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfPageTextExtractor {
  const PdfPageTextExtractor();

  Future<String> extractTextLayer({
    required String pdfPath,
    required int pageNumber,
  }) async {
    final file = File(pdfPath);
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    try {
      if (pageNumber < 1 || pageNumber > document.pages.count) return '';
      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText(
        startPageIndex: pageNumber - 1,
        endPageIndex: pageNumber - 1,
      );
      return _normalize(text);
    } finally {
      document.dispose();
    }
  }

  String _normalize(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
