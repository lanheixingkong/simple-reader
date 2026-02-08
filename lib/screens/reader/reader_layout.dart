import 'package:flutter/material.dart';

import '../../models/library.dart';
import '../../services/settings_store.dart';

class ReaderLayout extends StatelessWidget {
  const ReaderLayout({
    super.key,
    required this.book,
    required this.settings,
    required this.child,
    this.actions = const [],
  });

  final Book book;
  final ReaderSettings settings;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final background = SettingsStore.backgroundFor(settings.theme);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: Text(book.title),
        actions: actions,
      ),
      body: child,
    );
  }
}
