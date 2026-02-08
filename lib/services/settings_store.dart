import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderTheme { light, sepia, mint, slate, dark }

class ReaderSettings {
  const ReaderSettings({
    required this.fontSize,
    required this.theme,
  });

  final double fontSize;
  final ReaderTheme theme;

  ReaderSettings copyWith({double? fontSize, ReaderTheme? theme}) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      theme: theme ?? this.theme,
    );
  }
}

class SettingsStore {
  SettingsStore._();

  static final SettingsStore instance = SettingsStore._();

  static const _fontSizeKey = 'reader_font_size';
  static const _themeKey = 'reader_theme';

  Future<ReaderSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fontSize = prefs.getDouble(_fontSizeKey) ?? 18;
    final themeName = prefs.getString(_themeKey) ?? 'light';
    final theme = ReaderTheme.values.firstWhere(
      (item) => item.name == themeName,
      orElse: () => ReaderTheme.light,
    );
    return ReaderSettings(fontSize: fontSize, theme: theme);
  }

  Future<void> save(ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, settings.fontSize);
    await prefs.setString(_themeKey, settings.theme.name);
  }

  static Color backgroundFor(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return const Color(0xFFFAFAF7);
      case ReaderTheme.sepia:
        return const Color(0xFFF2E7D5);
      case ReaderTheme.mint:
        return const Color(0xFFE7F2EC);
      case ReaderTheme.slate:
        return const Color(0xFFE8EEF5);
      case ReaderTheme.dark:
        return const Color(0xFF121212);
    }
  }

  static Color textFor(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
      case ReaderTheme.sepia:
      case ReaderTheme.mint:
      case ReaderTheme.slate:
        return const Color(0xFF1D1D1D);
      case ReaderTheme.dark:
        return const Color(0xFFEDEDED);
    }
  }
}
