import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/library.dart';
import '../../services/settings_store.dart';

class ReaderLayout extends StatefulWidget {
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
  State<ReaderLayout> createState() => _ReaderLayoutState();
}

class _ReaderLayoutState extends State<ReaderLayout> {
  static const _readerGuideSeenKey = 'reader_usage_guide_seen_v1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowFirstUseGuide();
    });
  }

  Future<void> _maybeShowFirstUseGuide() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_readerGuideSeenKey) ?? false;
    if (seen || !mounted) return;
    await _showUsageGuide();
    await prefs.setBool(_readerGuideSeenKey, true);
  }

  Future<void> _showUsageGuide() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('阅读页操作说明'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. 左侧点击上一页，右侧点击下一页。'),
            SizedBox(height: 8),
            Text('2. 中间点击可显示/隐藏顶部与底部工具栏。'),
            SizedBox(height: 8),
            Text('3. 长按文字可选中，并使用复制、分享、AI问答。'),
            SizedBox(height: 8),
            Text('4. 底部工具栏可调字体/背景，并打开 AI 问答。'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final background = SettingsStore.backgroundFor(settings.theme);
    final appBarBackground = _appBarBackgroundFor(background);
    final appBarForeground = _appBarForegroundFor(appBarBackground);
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          Positioned.fill(child: SafeArea(bottom: false, child: widget.child)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              bottom: false,
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.showAppBarListenable,
                builder: (context, showAppBar, _) {
                  final topInset = MediaQuery.of(context).padding.top;
                  return IgnorePointer(
                    ignoring: !showAppBar,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: showAppBar ? 1 : 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 180),
                        offset: showAppBar
                            ? Offset.zero
                            : const Offset(0, -0.1),
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
                                    widget.book.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontSize: 16),
                                  ),
                                  actions: [
                                    ...widget.actions,
                                    IconButton(
                                      onPressed: _showUsageGuide,
                                      icon: const Icon(Icons.help_outline),
                                      tooltip: '操作说明',
                                    ),
                                  ],
                                  backgroundColor: appBarBackground,
                                  surfaceTintColor: Colors.transparent,
                                  scrolledUnderElevation: 0,
                                  foregroundColor: appBarForeground,
                                  iconTheme: IconThemeData(
                                    color: appBarForeground,
                                  ),
                                  actionsIconTheme: IconThemeData(
                                    color: appBarForeground,
                                  ),
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
                valueListenable: widget.showAppBarListenable,
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
                                        children: widget.bottomActions,
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
      return Colors.white.withValues(alpha: 0.92);
    }
    return Colors.black.withValues(alpha: 0.87);
  }
}
