import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/card_item.dart';
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
  int _index = 0;
  bool _loading = true;
  Object? _loadError;
  List<CardItem> _items = const <CardItem>[];
  final Map<String, String> _imageUrlCache = <String, String>{};
  final Map<String, int> _scores = <String, int>{};
  final Map<String, bool> _saving = <String, bool>{};
  final Map<String, bool> _saved = <String, bool>{};
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
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
      final items = await repo.listCards(widget.tabId);
      List<StudentVote> votes = const <StudentVote>[];
      try {
        votes = await api.fetchMyVotes(
          publicToken: widget.publicToken,
          tabId: widget.tabId,
          studentName: widget.studentName,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kon eerdere stemmen niet laden: $e')),
          );
        }
      }
      if (!mounted) return;
      for (final v in votes) {
        _scores[v.rankingItemId] = v.score;
        _saved[v.rankingItemId] = true;
      }
      for (final item in items) {
        _scores.putIfAbsent(item.id, () => 5);
      }
      setState(() {
        _items = items;
        _index = 0;
        _loading = false;
      });
      await _primeForIndex(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _primeForIndex(int idx) async {
    if (idx < 0 || idx >= _items.length) return;
    final drive = ref.read(driveApiProvider);

    Future<void> ensure(String fileId) async {
      if (fileId.trim().isEmpty || _imageUrlCache.containsKey(fileId)) return;
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

    await ensure(_items[idx].imageDriveFileId);
    if (idx - 1 >= 0) {
      // ignore: unawaited_futures
      ensure(_items[idx - 1].imageDriveFileId);
    }
    if (idx + 1 < _items.length) {
      // ignore: unawaited_futures
      ensure(_items[idx + 1].imageDriveFileId);
    }
  }

  void _go(int next) {
    if (next < 0 || next >= _items.length) return;
    setState(() => _index = next);
    _primeForIndex(next);
  }

  Future<void> _submit(CardItem item) async {
    if (_saving[item.id] == true) return;
    final score = _scores[item.id] ?? 5;
    setState(() => _saving[item.id] = true);
    try {
      await ref.read(rankingApiProvider).submitVote(
            publicToken: widget.publicToken,
            rankingItemId: item.id,
            studentName: widget.studentName,
            score: score,
          );
      if (!mounted) return;
      setState(() {
        _saved[item.id] = true;
        _saving[item.id] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stem opgeslagen.')),
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
    final TextStyle? counterStyle =
        accent != null ? TextStyle(color: foregroundOnTabColor(accent)) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tabTitle),
        backgroundColor: accent,
        foregroundColor: accent != null ? foregroundOnTabColor(accent) : null,
        actions: _items.isEmpty
            ? null
            : <Widget>[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '${_index + 1} / ${_items.length}',
                      style: counterStyle,
                    ),
                  ),
                ),
              ],
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

    final item = _items[_index];
    final url = _imageUrlCache[item.imageDriveFileId];
    final score = _scores[item.id] ?? 5;
    final isSaving = _saving[item.id] == true;
    final wasSaved = _saved[item.id] == true;
    final hasPrev = _index > 0;
    final hasNext = _index < _items.length - 1;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (hasPrev) _go(_index - 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (hasNext) _go(_index + 1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                (item.title ?? '').trim().isNotEmpty
                    ? item.title!.trim()
                    : 'Foto ${_index + 1}',
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (wasSaved)
                Text(
                  'Je hebt al gestemd — je kunt je stem aanpassen.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: url != null
                            ? Image.network(
                                url,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Text('Afbeelding laden mislukt'),
                                  );
                                },
                              )
                            : const Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(strokeWidth: 3),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Score: $score / 10',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 72,
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        children: List<Widget>.generate(5, (i) {
                          return _scoreButton(
                            context,
                            value: i + 1,
                            score: score,
                            isSaving: isSaving,
                            onPick: () => setState(() => _scores[item.id] = i + 1),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Row(
                        children: List<Widget>.generate(5, (i) {
                          final n = i + 6;
                          return _scoreButton(
                            context,
                            value: n,
                            score: score,
                            isSaving: isSaving,
                            onPick: () => setState(() => _scores[item.id] = n),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: isSaving ? null : () => _submit(item),
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(wasSaved ? 'Stem bijwerken' : 'Stem opslaan'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: Row(
                  children: <Widget>[
                    IconButton.filledTonal(
                      onPressed: hasPrev ? () => _go(_index - 1) : null,
                      icon: const Icon(Icons.arrow_left),
                      tooltip: 'Vorige foto',
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Foto ${_index + 1} van ${_items.length}',
                          style: Theme.of(context).textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: hasNext ? () => _go(_index + 1) : null,
                      icon: const Icon(Icons.arrow_right),
                      tooltip: 'Volgende foto',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreButton(
    BuildContext context, {
    required int value,
    required int score,
    required bool isSaving,
    required VoidCallback onPick,
  }) {
    final theme = Theme.of(context);
    final selected = score == value;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: isSaving ? null : onPick,
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: Text(
                '$value',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
