import 'package:flutter_test/flutter_test.dart';
import 'package:simple_reader/services/reading_stats_store.dart';

void main() {
  test('splits reading intervals across local calendar days', () {
    final data = ReadingStatsData();

    data.addInterval(
      DateTime(2026, 6, 9, 23, 50),
      DateTime(2026, 6, 10, 0, 20),
    );

    expect(data.dailyMilliseconds['2026-06-09'], 10 * 60 * 1000);
    expect(data.dailyMilliseconds['2026-06-10'], 20 * 60 * 1000);
    expect(data.totalDuration, const Duration(minutes: 30));
  });

  test('aggregates daily records by week, month, year and total', () {
    final data = ReadingStatsData({
      '2026-06-08': const Duration(minutes: 10).inMilliseconds,
      '2026-06-10': const Duration(minutes: 20).inMilliseconds,
      '2026-06-15': const Duration(minutes: 30).inMilliseconds,
      '2027-01-01': const Duration(minutes: 40).inMilliseconds,
    });

    final weeks = data.aggregate(ReadingStatsPeriod.week);
    final months = data.aggregate(ReadingStatsPeriod.month);
    final years = data.aggregate(ReadingStatsPeriod.year);
    final total = data.aggregate(ReadingStatsPeriod.total);

    expect(weeks, hasLength(3));
    expect(weeks[1].start, DateTime(2026, 6, 15));
    expect(weeks[1].duration, const Duration(minutes: 30));
    expect(weeks[2].start, DateTime(2026, 6, 8));
    expect(weeks[2].duration, const Duration(minutes: 30));
    expect(months, hasLength(2));
    expect(months.last.duration, const Duration(minutes: 60));
    expect(years, hasLength(2));
    expect(years.last.duration, const Duration(minutes: 60));
    expect(total.single.duration, const Duration(minutes: 100));
  });

  test('ignores invalid and non-positive persisted records', () {
    final data = ReadingStatsData.fromJson({
      'dailyMilliseconds': {
        '2026-06-10': 1200,
        '2026-06-11': 0,
        '2026-06-12': -10,
        'invalid': 'value',
      },
    });

    expect(data.dailyMilliseconds, {'2026-06-10': 1200});
  });
}
