import 'package:flutter/material.dart';

import '../../services/settings_store.dart';

class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({super.key, required this.settings});

  final ReaderSettings settings;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late double _fontSize;
  late ReaderTheme _theme;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.settings.fontSize;
    _theme = widget.settings.theme;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '阅读设置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text('字号 ${_fontSize.toStringAsFixed(0)}'),
            Slider(
              value: _fontSize,
              min: 14,
              max: 28,
              divisions: 14,
              label: _fontSize.toStringAsFixed(0),
              onChanged: (value) => setState(() => _fontSize = value),
            ),
            const SizedBox(height: 8),
            const Text('背景'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ReaderTheme.values.map((theme) {
                final selected = _theme == theme;
                return ChoiceChip(
                  label: Text(theme.name),
                  selected: selected,
                  onSelected: (_) => setState(() => _theme = theme),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      ReaderSettings(fontSize: _fontSize, theme: _theme),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
