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
    this.showAppBar = true,
  });

  final Book book;
  final ReaderSettings settings;
  final Widget child;
  final List<Widget> actions;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final background = SettingsStore.backgroundFor(settings.theme);
    final appBarBackground = _appBarBackgroundFor(background);
    final appBarForeground = _appBarForegroundFor(appBarBackground);
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: child,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: IgnorePointer(
                ignoring: !showAppBar,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: showAppBar ? 1 : 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 180),
                    offset: showAppBar ? Offset.zero : const Offset(0, -0.1),
                    child: SizedBox(
                      height: kToolbarHeight,
                      child: AppBar(
                        title: Text(book.title),
                        actions: actions,
                        backgroundColor: appBarBackground,
                        foregroundColor: appBarForeground,
                        iconTheme: IconThemeData(color: appBarForeground),
                        actionsIconTheme:
                            IconThemeData(color: appBarForeground),
                        elevation: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _appBarBackgroundFor(Color background) {
    final luminance = background.computeLuminance();
    if (luminance < 0.2) {
      return Color.lerp(background, Colors.white, 0.08)!;
    }
    return Color.lerp(background, Colors.black, 0.06)!;
  }

  Color _appBarForegroundFor(Color background) {
    final luminance = background.computeLuminance();
    if (luminance < 0.2) {
      return Colors.white.withOpacity(0.92);
    }
    return Colors.black.withOpacity(0.87);
  }
}
