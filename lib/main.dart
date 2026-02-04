import 'package:flutter/material.dart';

import 'screens/bookshelf_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SimpleReaderApp());
}

class SimpleReaderApp extends StatelessWidget {
  const SimpleReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF425C5A)),
        useMaterial3: true,
      ),
      home: const BookshelfScreen(),
    );
  }
}
