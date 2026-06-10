import 'package:flutter/material.dart';

import '../services/reading_stats_store.dart';

class ReadingStatsScreen extends StatefulWidget {
  const ReadingStatsScreen({super.key});

  @override
  State<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends State<ReadingStatsScreen> {
  ReadingStatsData? _data;
  ReadingStatsPeriod _period = ReadingStatsPeriod.day;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ReadingStatsStore.instance.load();
    if (!mounted) return;
    setState(() => _data = data);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('阅读统计')),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(data),
    );
  }

  Widget _buildContent(ReadingStatsData data) {
    final entries = data.aggregate(_period);
    final maxMilliseconds = entries.fold<int>(
      0,
      (max, entry) => entry.duration.inMilliseconds > max
          ? entry.duration.inMilliseconds
          : max,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('累计阅读', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  _formatDuration(data.totalDuration),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<ReadingStatsPeriod>(
            segments: const [
              ButtonSegment(value: ReadingStatsPeriod.day, label: Text('日')),
              ButtonSegment(value: ReadingStatsPeriod.week, label: Text('周')),
              ButtonSegment(value: ReadingStatsPeriod.month, label: Text('月')),
              ButtonSegment(value: ReadingStatsPeriod.year, label: Text('年')),
              ButtonSegment(value: ReadingStatsPeriod.total, label: Text('总计')),
            ],
            selected: {_period},
            showSelectedIcon: false,
            onSelectionChanged: (selected) {
              setState(() => _period = selected.first);
            },
          ),
        ),
        const SizedBox(height: 20),
        if (entries.isEmpty || data.totalDuration == Duration.zero)
          const Padding(
            padding: EdgeInsets.only(top: 64),
            child: Center(child: Text('还没有阅读记录')),
          )
        else
          for (final entry in entries)
            _StatsEntryTile(
              entry: entry,
              fraction: maxMilliseconds == 0
                  ? 0
                  : entry.duration.inMilliseconds / maxMilliseconds,
            ),
      ],
    );
  }
}

class _StatsEntryTile extends StatelessWidget {
  const _StatsEntryTile({required this.entry, required this.fraction});

  final ReadingStatsEntry entry;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(entry.label)),
              Text(
                _formatDuration(entry.duration),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 1) return duration > Duration.zero ? '不足 1 分钟' : '0 分钟';
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours == 0) return '$minutes 分钟';
  if (remainingMinutes == 0) return '$hours 小时';
  return '$hours 小时 $remainingMinutes 分钟';
}
