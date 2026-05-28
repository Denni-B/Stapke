import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/tab_category.dart';
import '../../services/classroom/classroom_api.dart';
import '../../utils/tab_color.dart';

class TeacherNameVotingResultsScreen extends ConsumerStatefulWidget {
  const TeacherNameVotingResultsScreen({
    super.key,
    required this.userId,
    required this.tab,
  });

  final String userId;
  final TabCategory tab;

  @override
  ConsumerState<TeacherNameVotingResultsScreen> createState() =>
      _TeacherNameVotingResultsScreenState();
}

class _TeacherNameVotingResultsScreenState extends ConsumerState<TeacherNameVotingResultsScreen> {
  late Future<List<NameVoteResultItem>> _future;
  int? _touchedIndex;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(classroomApiProvider).teacherNameVoteResults(tabId: widget.tab.id);
  }

  Color _sliceColor(int i, ColorScheme scheme) {
    const palette = <Color>[
      Color(0xFF2F6BFF),
      Color(0xFF00B894),
      Color(0xFFFF8A00),
      Color(0xFFE84393),
      Color(0xFF6C5CE7),
      Color(0xFF00A8FF),
      Color(0xFFFF4757),
      Color(0xFF2ED573),
      Color(0xFF5352ED),
      Color(0xFFFFA502),
    ];
    final base = palette[i % palette.length];
    // Slightly adapt for high-contrast themes.
    final bool dark = scheme.brightness == Brightness.dark;
    return dark ? base.withValues(alpha: 0.95) : base;
  }

  @override
  Widget build(BuildContext context) {
    final Color? accent = parseTabColorHex(widget.tab.tabColorHex);
    return Scaffold(
      appBar: AppBar(
        title: Text('Resultaten — ${widget.tab.title}'),
        backgroundColor: accent,
        foregroundColor: accent != null ? foregroundOnTabColor(accent) : null,
        actions: <Widget>[
          IconButton(
            tooltip: 'Vernieuwen',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _reload());
            },
          ),
        ],
      ),
      body: FutureBuilder<List<NameVoteResultItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Fout: ${snap.error}'));
          }
          final items = snap.data ?? const <NameVoteResultItem>[];
          if (items.isEmpty) {
            return const Center(child: Text('Nog geen stemmen.'));
          }

          final totalPoints = items.fold<int>(0, (a, it) => a + it.pointsTotal);
          final scheme = Theme.of(context).colorScheme;

          final sections = <PieChartSectionData>[
            for (var i = 0; i < items.length; i++)
              PieChartSectionData(
                value: max(0, items[i].pointsTotal).toDouble(),
                color: _sliceColor(i, scheme),
                radius: _touchedIndex == i ? 74 : 64,
                showTitle: false,
              ),
          ];

          final touched = (_touchedIndex != null &&
                  _touchedIndex! >= 0 &&
                  _touchedIndex! < items.length)
              ? items[_touchedIndex!]
              : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Puntenverdeling',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Totaal: $totalPoints punten',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      AspectRatio(
                        aspectRatio: 1.4,
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: PieChart(
                                PieChartData(
                                  sections: sections,
                                  centerSpaceRadius: 32,
                                  pieTouchData: PieTouchData(
                                    touchCallback: (event, resp) {
                                      final idx = resp?.touchedSection?.touchedSectionIndex;
                                      if (!mounted) return;
                                      setState(() {
                                        _touchedIndex = (event.isInterestedForInteractions &&
                                                idx != null &&
                                                idx >= 0)
                                            ? idx
                                            : null;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 210,
                              child: touched == null
                                  ? Text(
                                      'Tik op een stuk van de taart om details te zien.',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    )
                                  : _TouchedDetails(
                                      color: _sliceColor(_touchedIndex!, scheme),
                                      name: touched.name,
                                      points: touched.pointsTotal,
                                      totalPoints: totalPoints,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Ranglijst', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...List<Widget>.generate(items.length, (i) {
                final it = items[i];
                final color = _sliceColor(i, scheme);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(color: foregroundOnTabColor(color)),
                      ),
                    ),
                    title: Text(it.name),
                    trailing: Text(
                      '${it.pointsTotal} p',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    onTap: () => setState(() => _touchedIndex = i),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _TouchedDetails extends StatelessWidget {
  const _TouchedDetails({
    required this.color,
    required this.name,
    required this.points,
    required this.totalPoints,
  });

  final Color color;
  final String name;
  final int points;
  final int totalPoints;

  @override
  Widget build(BuildContext context) {
    final pct = totalPoints <= 0 ? 0 : (points / totalPoints * 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('$points punten', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${pct.toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

