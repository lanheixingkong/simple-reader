import 'dart:async';
import 'dart:convert';

import 'app_storage.dart';

enum ReadingStatsPeriod { day, week, month, year, total }

class ReadingStatsEntry {
  const ReadingStatsEntry({
    required this.start,
    required this.duration,
    required this.label,
  });

  final DateTime? start;
  final Duration duration;
  final String label;
}

class ReadingStatsData {
  ReadingStatsData([Map<String, int>? dailyMilliseconds])
    : dailyMilliseconds = dailyMilliseconds ?? <String, int>{};

  final Map<String, int> dailyMilliseconds;

  Duration get totalDuration => Duration(
    milliseconds: dailyMilliseconds.values.fold(0, (sum, value) => sum + value),
  );

  void addInterval(DateTime start, DateTime end) {
    if (!end.isAfter(start)) return;
    var cursor = start;
    while (cursor.isBefore(end)) {
      final nextDay = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final segmentEnd = end.isBefore(nextDay) ? end : nextDay;
      final milliseconds = segmentEnd.difference(cursor).inMilliseconds;
      if (milliseconds > 0) {
        final key = dateKey(cursor);
        dailyMilliseconds[key] = (dailyMilliseconds[key] ?? 0) + milliseconds;
      }
      cursor = segmentEnd;
    }
  }

  List<ReadingStatsEntry> aggregate(ReadingStatsPeriod period) {
    if (period == ReadingStatsPeriod.total) {
      return [
        ReadingStatsEntry(start: null, duration: totalDuration, label: '全部阅读'),
      ];
    }

    final grouped = <DateTime, int>{};
    for (final entry in dailyMilliseconds.entries) {
      final date = parseDateKey(entry.key);
      if (date == null || entry.value <= 0) continue;
      final start = periodStart(date, period);
      grouped[start] = (grouped[start] ?? 0) + entry.value;
    }
    final starts = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final start in starts)
        ReadingStatsEntry(
          start: start,
          duration: Duration(milliseconds: grouped[start]!),
          label: periodLabel(start, period),
        ),
    ];
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'dailyMilliseconds': dailyMilliseconds,
  };

  static ReadingStatsData fromJson(Object? value) {
    if (value is! Map) return ReadingStatsData();
    final raw = value['dailyMilliseconds'];
    if (raw is! Map) return ReadingStatsData();
    final daily = <String, int>{};
    for (final entry in raw.entries) {
      final milliseconds = entry.value;
      if (milliseconds is num && milliseconds > 0) {
        daily[entry.key.toString()] = milliseconds.toInt();
      }
    }
    return ReadingStatsData(daily);
  }

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime? parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  static DateTime periodStart(DateTime date, ReadingStatsPeriod period) {
    switch (period) {
      case ReadingStatsPeriod.day:
        return DateTime(date.year, date.month, date.day);
      case ReadingStatsPeriod.week:
        final day = DateTime(date.year, date.month, date.day);
        return day.subtract(Duration(days: day.weekday - DateTime.monday));
      case ReadingStatsPeriod.month:
        return DateTime(date.year, date.month);
      case ReadingStatsPeriod.year:
        return DateTime(date.year);
      case ReadingStatsPeriod.total:
        return DateTime(1970);
    }
  }

  static String periodLabel(DateTime start, ReadingStatsPeriod period) {
    switch (period) {
      case ReadingStatsPeriod.day:
        return '${start.year}年${start.month}月${start.day}日';
      case ReadingStatsPeriod.week:
        final end = start.add(const Duration(days: 6));
        return '${start.month}月${start.day}日 - ${end.month}月${end.day}日';
      case ReadingStatsPeriod.month:
        return '${start.year}年${start.month}月';
      case ReadingStatsPeriod.year:
        return '${start.year}年';
      case ReadingStatsPeriod.total:
        return '全部阅读';
    }
  }
}

class ReadingStatsStore {
  ReadingStatsStore._();

  static final ReadingStatsStore instance = ReadingStatsStore._();

  ReadingStatsData? _data;
  Future<void> _writeQueue = Future<void>.value();

  Future<ReadingStatsData> load() async {
    await _writeQueue.catchError((_) {});
    return _load();
  }

  Future<void> addSession(DateTime start, DateTime end) {
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      final data = await _load();
      data.addInterval(start, end);
      await _persist(data);
    });
    return _writeQueue;
  }

  Future<ReadingStatsData> _load() async {
    final cached = _data;
    if (cached != null) return cached;
    final file = await AppStorage.instance.file('reading_stats.json');
    if (!await file.exists()) {
      return _data = ReadingStatsData();
    }
    try {
      final raw = await file.readAsString();
      return _data = ReadingStatsData.fromJson(jsonDecode(raw));
    } catch (_) {
      return _data = ReadingStatsData();
    }
  }

  Future<void> _persist(ReadingStatsData data) async {
    final file = await AppStorage.instance.file('reading_stats.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data.toJson()));
  }
}
