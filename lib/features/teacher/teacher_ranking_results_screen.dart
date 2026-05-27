import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/card_item.dart';
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

  final CardItem item;
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
  late Future<({List<CardItem> items, List<RankingSubmission> submissions})> _dataFuture;
  final Map<String, String> _thumbCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final repo = ref.read(teacherRepositoryProvider);
    _dataFuture = () async {
      final items = await repo.listCards(tabId: widget.tab.id);
      final submissions = await repo.listRankingSubmissions(tabId: widget.tab.id);
      return (items: items, submissions: submissions);
    }();
  }

  List<_ItemStats> _buildStats(
    List<CardItem> items,
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
      body: FutureBuilder<({List<CardItem> items, List<RankingSubmission> submissions})>(
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('Detail per foto', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final int crossAxisCount = w >= 1200
                      ? 5
                      : (w >= 900 ? 4 : (w >= 600 ? 3 : 2));
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: stats.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.92,
                    ),
                    itemBuilder: (context, index) {
                      return _StatsGridTile(
                        stats: stats[index],
                        thumbLoader: _thumb,
                      );
                    },
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsGridTile extends StatelessWidget {
  const _StatsGridTile({required this.stats, required this.thumbLoader});

  final _ItemStats stats;
  final Future<String?> Function(String fileId) thumbLoader;

  void _openDetails(BuildContext context) {
    final s = stats;
    final dateFmt = DateFormat('d MMM yyyy, HH:mm');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  (s.item.title ?? '').trim().isNotEmpty ? s.item.title!.trim() : 'Foto',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  s.count == 0
                      ? 'Nog geen stemmen'
                      : 'Gemiddelde: ${s.average!.toStringAsFixed(1)} / 10 · ${s.count} stem${s.count == 1 ? '' : 'men'}',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (s.submissions.isEmpty)
                  const SizedBox.shrink()
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: s.submissions.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final sub = s.submissions[index];
                        return ListTile(
                          dense: true,
                          title: Text('${sub.studentName} — ${sub.score}/10'),
                          subtitle: Text(
                            dateFmt.format(DateTime.parse(sub.updatedAtIso).toLocal()),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final title = (s.item.title ?? '').trim().isNotEmpty ? s.item.title!.trim() : 'Foto';
    final subtitle = s.count == 0
        ? 'Nog geen stemmen'
        : '${s.average!.toStringAsFixed(1)} / 10 · ${s.count} stem${s.count == 1 ? '' : 'men'}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetails(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: FutureBuilder<String?>(
                future: thumbLoader(s.item.imageDriveFileId),
                builder: (context, imgSnap) {
                  final url = imgSnap.data;
                  return ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: url == null
                        ? const Center(child: Icon(Icons.image_outlined, size: 32))
                        : Image.network(url, fit: BoxFit.cover),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
