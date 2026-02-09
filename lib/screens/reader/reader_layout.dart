import 'package:flutter/foundation.dart';
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
    this.bottomActions = const [],
    required this.showAppBarListenable,
  });

  final Book book;
  final ReaderSettings settings;
  final Widget child;
  final List<Widget> actions;
  final List<Widget> bottomActions;
  final ValueListenable<bool> showAppBarListenable;

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
              top: false,
              bottom: false,
              child: ValueListenableBuilder<bool>(
                valueListenable: showAppBarListenable,
                builder: (context, showAppBar, _) {
                  final topInset = MediaQuery.of(context).padding.top;
                  return IgnorePointer(
                    ignoring: !showAppBar,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: showAppBar ? 1 : 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 180),
                        offset: showAppBar ? Offset.zero : const Offset(0, -0.1),
                        child: SizedBox(
                          height: kToolbarHeight + topInset,
                          child: Material(
                            color: appBarBackground,
                            elevation: 2,
                            child: Padding(
                              padding: EdgeInsets.only(top: topInset),
                              child: SizedBox(
                                height: kToolbarHeight,
                                child: AppBar(
                                  primary: false,
                                  title: Text(
                                    book.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontSize: 16),
                                  ),
                                  actions: actions,
                                  backgroundColor: appBarBackground,
                                  surfaceTintColor: Colors.transparent,
                                  scrolledUnderElevation: 0,
                                  foregroundColor: appBarForeground,
                                  iconTheme:
                                      IconThemeData(color: appBarForeground),
                                  actionsIconTheme:
                                      IconThemeData(color: appBarForeground),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              bottom: false,
              child: ValueListenableBuilder<bool>(
                valueListenable: showAppBarListenable,
                builder: (context, showAppBar, _) {
                  final bottomInset = MediaQuery.of(context).padding.bottom;
                  const barHeight = kToolbarHeight - 12;
                  const leadingInset = 12.0;
                  return IgnorePointer(
                    ignoring: !showAppBar,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: showAppBar ? 1 : 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 180),
                        offset: showAppBar ? Offset.zero : const Offset(0, 0.1),
                        child: SizedBox(
                          height: barHeight + bottomInset,
                          child: Material(
                            color: appBarBackground,
                            elevation: 2,
                            child: Padding(
                              padding: EdgeInsets.only(bottom: bottomInset),
                              child: IconButtonTheme(
                                data: IconButtonThemeData(
                                  style: IconButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 0,
                                    ),
                                    minimumSize: const Size(44, 40),
                                    iconSize: 26,
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 0),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: leadingInset,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: bottomActions,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
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
