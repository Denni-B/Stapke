import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ranking_item.dart';
import '../../services/appwrite/student_repository.dart';
import '../../services/drive/drive_api.dart';
import '../../services/ranking/ranking_api.dart';
import '../../utils/tab_color.dart';

class RankingViewerScreen extends ConsumerStatefulWidget {
  const RankingViewerScreen({
    super.key,
    required this.publicToken,
    required this.tabId,
    required this.tabTitle,
    required this.studentName,
    this.tabColorHex,
  });

  final String publicToken;
  final String tabId;
  final String tabTitle;
  final String studentName;
  final String? tabColorHex;

  @override
  ConsumerState<RankingViewerScreen> createState() => _RankingViewerScreenState();
}

class _RankingViewerScreenState extends ConsumerState<RankingViewerScreen> {
  bool _loading = true;
  Object? _loadError;
  List<RankingItem> _items = const <RankingItem>[];
  final Map<String, String> _imageUrlCache = <String, String>{};
  final Map<String, int> _scores = <String, int>{};
  final Map<String, TextEditingController> _commentControllers = <String, TextEditingController>{};
  final Map<String, bool> _saving = <String, bool>{};
  final Map<String, bool> _saved = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _commentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final repo = ref.read(studentRepositoryProvider);
      final api = ref.read(rankingApiProvider);
      final items = await repo.listRankingItems(widget.tabId);
      final votes = await api.fetchMyVotes(
        publicToken: widget.publicToken,
        tabId: widget.tabId,
        studentName: widget.studentName,
      );
      if (!mounted) return;
      for (final v in votes) {
        _scores[v.rankingItemId] = v.score;
        _saved[v.rankingItemId] = true;
      }
      for (final item in items) {
        var commentText = '';
        for (final v in votes) {
          if (v.rankingItemId == item.id) {
            commentText = v.comment;
            break;
          }
        }
        _commentControllers.putIfAbsent(
          item.id,
          () => TextEditingController(text: commentText),
        );
        _scores.putIfAbsent(item.id, () => 5);
      }
      setState(() {
        _items = items;
        _loading = false;
      });
      await _primeImages();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _primeImages() async {
    final drive = ref.read(driveApiProvider);
    for (final item in _items) {
      final fileId = item.imageDriveFileId;
      if (fileId.trim().isEmpty || _imageUrlCache.containsKey(fileId)) continue;
      try {
        final url = await drive.publicDownloadDataUrl(
          publicToken: widget.publicToken,
          fileId: fileId,
        );
        if (!mounted) return;
        setState(() => _imageUrlCache[fileId] = url);
      } catch (_) {
        // Best effort per image.
      }
    }
  }

  Future<void> _submit(RankingItem item) async {
    if (_saving[item.id] == true) return;
    final score = _scores[item.id] ?? 5;
    setState(() => _saving[item.id] = true);
    try {
      await ref.read(rankingApiProvider).submitVote(
            publicToken: widget.publicToken,
            rankingItemId: item.id,
            studentName: widget.studentName,
            score: score,
            comment: _commentControllers[item.id]?.text,
          );
      if (!mounted) return;
      setState(() {
        _saved[item.id] = true;
        _saving[item.id] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stem opgeslagen voor ${item.displayLabel}.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving[item.id] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opslaan mislukt: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color? accent = parseTabColorHex(widget.tabColorHex);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tabTitle),
        backgroundColor: accent,
        foregroundColor: accent != null ? foregroundOnTabColor(accent) : null,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(child: Text('Fout: $_loadError'));
    }
    if (_items.isEmpty) {
      return const Center(child: Text('Nog geen foto\'s in deze ranking.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 20),
      itemBuilder: (context, index) {
        final item = _items[index];
        final url = _imageUrlCache[item.imageDriveFileId];
        final score = _scores[item.id] ?? 5;
        final isSaving = _saving[item.id] == true;
        final wasSaved = _saved[item.id] == true;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (url != null)
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.network(url, fit: BoxFit.cover),
                )
              else
                const AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Center(child: CircularProgressIndicator()),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      item.displayLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (wasSaved)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Je hebt al gestemd — je kunt je stem aanpassen.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text('Score: $score / 10', style: Theme.of(context).textTheme.titleSmall),
                    Slider(
                      value: score.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '$score',
                      onChanged: isSaving
                          ? null
                          : (v) => setState(() => _scores[item.id] = v.round()),
                    ),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: List<Widget>.generate(10, (i) {
                        final n = i + 1;
                        final selected = score == n;
                        return ChoiceChip(
                          label: Text('$n'),
                          selected: selected,
                          onSelected: isSaving
                              ? null
                              : (_) => setState(() => _scores[item.id] = n),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _commentControllers[item.id],
                      decoration: const InputDecoration(
                        labelText: 'Opmerking (optioneel)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      maxLength: 500,
                      enabled: !isSaving,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: isSaving ? null : () => _submit(item),
                      child: isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(wasSaved ? 'Stem bijwerken' : 'Stem opslaan'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
