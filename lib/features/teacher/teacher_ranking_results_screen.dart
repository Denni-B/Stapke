import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/ranking_item.dart';
import '../../domain/models/ranking_submission.dart';
import '../../domain/models/tab_category.dart';
import '../../services/appwrite/teacher_repository.dart';
import '../../services/drive/drive_api.dart';
import '../../utils/tab_color.dart';

class _ItemStats {
  const _ItemStats({
    required this.item,
    required this.average,
    required this.count,
    required this.submissions,
  });

  final RankingItem item;
  final double? average;
  final int count;
  final List<RankingSubmission> submissions;
}

class TeacherRankingResultsScreen extends ConsumerStatefulWidget {
  const TeacherRankingResultsScreen({
    super.key,
    required this.userId,
    required this.tab,
  });

  final String userId;
  final TabCategory tab;

  @override
  ConsumerState<TeacherRankingResultsScreen> createState() =>
      _TeacherRankingResultsScreenState();
}

class _TeacherRankingResultsScreenState extends ConsumerState<TeacherRankingResultsScreen> {
  late Future<({List<RankingItem> items, List<RankingSubmission> submissions})> _dataFuture;
  final Map<String, String> _thumbCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final repo = ref.read(teacherRepositoryProvider);
    _dataFuture = () async {
      final items = await repo.listRankingItems(tabId: widget.tab.id);
      final submissions = await repo.listRankingSubmissions(tabId: widget.tab.id);
      return (items: items, submissions: submissions);
    }();
  }

  List<_ItemStats> _buildStats(
    List<RankingItem> items,
    List<RankingSubmission> submissions,
  ) {
    return items.map((item) {
      final subs =
          submissions.where((s) => s.rankingItemId == item.id).toList();
      if (subs.isEmpty) {
        return _ItemStats(item: item, average: null, count: 0, submissions: subs);
      }
      final sum = subs.fold<int>(0, (a, s) => a + s.score);
      return _ItemStats(
        item: item,
        average: sum / subs.length,
        count: subs.length,
        submissions: subs,
      );
    }).toList();
  }

  Future<String?> _thumb(String fileId) async {
    if (_thumbCache.containsKey(fileId)) return _thumbCache[fileId];
    try {
      final url = await ref.read(driveApiProvider).downloadDataUrl(fileId: fileId);
      _thumbCache[fileId] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color? accent = parseTabColorHex(widget.tab.tabColorHex);
    return Scaffold(
      appBar: AppBar(
        title: Text('Resultaten — ${widget.tab.title}'),
        backgroundColor: accent,
        foregroundColor: accent != null ? foregroundOnTabColor(accent) : null,
      ),
      body: FutureBuilder<({List<RankingItem> items, List<RankingSubmission> submissions})>(
        future: _dataFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Fout: ${snap.error}'));
          }
          final data = snap.data!;
          final stats = _buildStats(data.items, data.submissions);
          if (stats.isEmpty) {
            return const Center(child: Text('Nog geen foto\'s in deze ranking.'));
          }

          final withVotes = stats.where((s) => s.count > 0).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (withVotes.isNotEmpty) ...<Widget>[
                Text('Gemiddelde score per foto', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: 10,
                      minY: 0,
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 2,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= withVotes.length) return const SizedBox.shrink();
                              final label = withVotes[i].item.displayLabel;
                              final short = label.length > 8 ? '${label.substring(0, 8)}…' : label;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(short, style: const TextStyle(fontSize: 10)),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List<BarChartGroupData>.generate(withVotes.length, (i) {
                        final avg = withVotes[i].average ?? 0;
                        return BarChartGroupData(
                          x: i,
                          barRods: <BarChartRodData>[
                            BarChartRodData(
                              toY: avg,
                              width: 18,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Text('Detail per foto', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...stats.map((s) => _StatsCard(stats: s, thumbLoader: _thumb)),
            ],
          );
        },
      ),
    );
  }
}

class _StatsCard extends StatefulWidget {
  const _StatsCard({required this.stats, required this.thumbLoader});

  final _ItemStats stats;
  final Future<String?> Function(String fileId) thumbLoader;

  @override
  State<_StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<_StatsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final dateFmt = DateFormat('d MMM yyyy, HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FutureBuilder<String?>(
            future: widget.thumbLoader(s.item.imageDriveFileId),
            builder: (context, imgSnap) {
              final url = imgSnap.data;
              if (url == null) {
                return const SizedBox(
                  height: 120,
                  child: Center(child: Icon(Icons.image_outlined, size: 48)),
                );
              }
              return AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(url, fit: BoxFit.cover),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(s.item.displayLabel, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  s.count == 0
                      ? 'Nog geen stemmen'
                      : 'Gemiddelde: ${s.average!.toStringAsFixed(1)} / 10 · ${s.count} stem${s.count == 1 ? '' : 'men'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (s.submissions.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    label: Text(_expanded ? 'Stemmen verbergen' : 'Alle stemmen tonen'),
                  ),
                if (_expanded)
                  ...s.submissions.map(
                    (sub) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${sub.studentName} — ${sub.score}/10'),
                      subtitle: sub.comment != null
                          ? Text(sub.comment!)
                          : Text(dateFmt.format(DateTime.parse(sub.updatedAtIso).toLocal())),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
