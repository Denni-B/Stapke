import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/audio/app_audio_player.dart';
import '../../../services/appwrite/student_repository.dart';
import '../../../services/drive/drive_api.dart';
import '../../../domain/models/card_item.dart';
import '../../../domain/cards/card_types.dart';
import '../../../services/web/blob_url.dart';
import '../../../utils/tab_color.dart';
import '../../../domain/models/image_annotation.dart';
import 'card_types/image_fill_in_view.dart';

class CardViewerScreen extends ConsumerStatefulWidget {
  const CardViewerScreen({
    super.key,
    required this.publicToken,
    required this.tabId,
    required this.tabTitle,
    this.tabColorHex,
  });

  final String publicToken;
  final String tabId;
  final String tabTitle;
  final String? tabColorHex;

  @override
  ConsumerState<CardViewerScreen> createState() => _CardViewerScreenState();
}

class _CardViewerScreenState extends ConsumerState<CardViewerScreen> {
  int _index = 0;
  final AppAudioPlayer _player = AppAudioPlayer.create();
  bool _isPlaying = false;
  bool? _fillInIsCorrect;
  final FocusNode _focusNode = FocusNode();
  final BlobUrl _blobUrl = BlobUrl.create();

  bool _loading = true;
  Object? _loadError;
  List<CardItem> _cards = const <CardItem>[];

  final Map<String, String> _dataUrlCache = <String, String>{};
  final Map<String, String> _objectUrlCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();

    // Avoid `autofocus: true` on web: it can trigger focus traversal while this
    // element is being detached (inactive), causing findRenderObject errors.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final repo = ref.read(studentRepositoryProvider);
      final cards = await repo.listCards(widget.tabId);
      if (!mounted) return;
      setState(() {
        _cards = cards;
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
    if (idx < 0 || idx >= _cards.length) return;
    final drive = ref.read(driveApiProvider);

    Future<void> ensure(String fileId) async {
      if (fileId.trim().isEmpty) return;
      if (_dataUrlCache.containsKey(fileId)) return;
      final url = await drive.publicDownloadDataUrl(
        publicToken: widget.publicToken,
        fileId: fileId,
      );
      if (!mounted) return;
      setState(() => _dataUrlCache[fileId] = url);
    }

    final current = _cards[idx];
    await ensure(current.imageDriveFileId);
    await ensure(current.audioDriveFileId);

    // Preload adjacent images for smoother navigation.
    if (idx - 1 >= 0) {
      final prev = _cards[idx - 1];
      // Fire-and-forget.
      // ignore: unawaited_futures
      ensure(prev.imageDriveFileId);
    }
    if (idx + 1 < _cards.length) {
      final next = _cards[idx + 1];
      // ignore: unawaited_futures
      ensure(next.imageDriveFileId);
    }
  }

  @override
  void dispose() {
    _player.stop();
    _focusNode.dispose();
    for (final url in _objectUrlCache.values) {
      if (kIsWeb) _blobUrl.revokeObjectUrl(url);
    }
    super.dispose();
  }

  ({String mimeType, List<int> bytes})? _parseDataUrl(String dataUrl) {
    final prefix = 'data:';
    if (!dataUrl.startsWith(prefix)) return null;
    final comma = dataUrl.indexOf(',');
    if (comma <= 0) return null;
    final meta = dataUrl.substring(prefix.length, comma); // e.g. audio/mpeg;base64
    final isBase64 = meta.endsWith(';base64');
    if (!isBase64) return null;
    final mimeType = meta.substring(0, meta.length - ';base64'.length);
    final b64 = dataUrl.substring(comma + 1);
    try {
      return (mimeType: mimeType.isEmpty ? 'application/octet-stream' : mimeType, bytes: base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  void _go(int next) {
    if (next < 0 || next >= _cards.length) return;
    setState(() {
      _index = next;
      _fillInIsCorrect = null;
    });
    _stopAudio();
    _primeForIndex(next);
  }

  void _stopAudio() {
    _player.stop();
    setState(() => _isPlaying = false);
  }

  Future<void> _togglePlay() async {
    final card = _cards[_index];
    if (card.audioDriveFileId.trim().isEmpty) return;
    final String? audioUrl = _dataUrlCache[card.audioDriveFileId];
    if (audioUrl == null) return;

    if (!kIsWeb) return;

    if (_isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
      return;
    }

    try {
      var urlToPlay = audioUrl;
      if (audioUrl.startsWith('data:')) {
        final cached = _objectUrlCache[card.audioDriveFileId];
        if (cached != null) {
          urlToPlay = cached;
        } else {
          final parsed = _parseDataUrl(audioUrl);
          if (parsed != null) {
            final fromCard = card.audioMimeType.split(';').first.trim();
            final fromData = parsed.mimeType.split(';').first.trim();
            final mimeForPlay =
                fromCard.startsWith('audio/') ? fromCard : fromData;
            final objectUrl = _blobUrl.createObjectUrl(
              bytes: parsed.bytes,
              mimeType: mimeForPlay,
            );
            _objectUrlCache[card.audioDriveFileId] = objectUrl;
            urlToPlay = objectUrl;
          }
        }
      }

      await _player.load(urlToPlay);
      await _player.play();
      if (!mounted) return;
      setState(() => _isPlaying = true);

      _player.onEnded.listen((_) {
        if (!mounted) return;
        setState(() => _isPlaying = false);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Afspelen van audio mislukt: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: buildTabColoredAppBar(
          context,
          title: widget.tabTitle,
          tabColorHex: widget.tabColorHex,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: buildTabColoredAppBar(
          context,
          title: widget.tabTitle,
          tabColorHex: widget.tabColorHex,
        ),
        body: Center(child: Text('Kaarten laden mislukt: $_loadError')),
      );
    }
    if (_cards.isEmpty) {
      return Scaffold(
        appBar: buildTabColoredAppBar(
          context,
          title: widget.tabTitle,
          tabColorHex: widget.tabColorHex,
        ),
        body: const Center(child: Text('Nog geen kaarten.')),
      );
    }

    final CardItem card = _cards[_index];
    final String? imageUrl = card.imageDriveFileId.trim().isEmpty
        ? null
        : _dataUrlCache[card.imageDriveFileId];
    final bool hasPrev = _index > 0;
    final bool hasNext = _index < _cards.length - 1;
    final type = CardTypeRegistry.normalizeType(card.cardType);

    final Color? accent = parseTabColorHex(widget.tabColorHex);
    final TextStyle? counterStyle = accent != null
        ? TextStyle(color: foregroundOnTabColor(accent))
        : null;

    return Scaffold(
      appBar: buildTabColoredAppBar(
        context,
        title: widget.tabTitle,
        tabColorHex: widget.tabColorHex,
        actions: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${_index + 1} / ${_cards.length}',
                style: counterStyle,
              ),
            ),
          ),
        ],
      ),
      body: Focus(
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
        child: (type == CardTypeIds.imageFillIn)
            ? Column(
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ImageFillInCardView(
                        card: card,
                        imageUrl: imageUrl,
                        onResultChanged: (v) {
                          if (!mounted) return;
                          setState(() => _fillInIsCorrect = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: <Widget>[
                        IconButton.filledTonal(
                          onPressed: hasPrev ? () => _go(_index - 1) : null,
                          icon: const Icon(Icons.arrow_left),
                          tooltip: 'Vorige',
                        ),
                        Expanded(
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: _fillInIsCorrect == null
                                  ? const SizedBox.shrink()
                                  : Icon(
                                      _fillInIsCorrect!
                                          ? Icons.sentiment_satisfied_alt_rounded
                                          : Icons.sentiment_dissatisfied_rounded,
                                      key: ValueKey<bool>(_fillInIsCorrect!),
                                      size: 38,
                                      color: _fillInIsCorrect!
                                          ? Colors.green
                                          : Theme.of(context).colorScheme.error,
                                    ),
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: hasNext ? () => _go(_index + 1) : null,
                          icon: const Icon(Icons.arrow_right),
                          tooltip: 'Volgende',
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : (type == CardTypeIds.ranking)
            ? Column(
                children: <Widget>[
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ColoredBox(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: imageUrl == null
                                ? const Center(child: Text('Afbeelding ontbreekt'))
                                : Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(
                                        child: Text('Afbeelding laden mislukt'),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: <Widget>[
                        IconButton.filledTonal(
                          onPressed: hasPrev ? () => _go(_index - 1) : null,
                          icon: const Icon(Icons.arrow_left),
                          tooltip: 'Vorige',
                        ),
                        const Spacer(),
                        IconButton.filledTonal(
                          onPressed: hasNext ? () => _go(_index + 1) : null,
                          icon: const Icon(Icons.arrow_right),
                          tooltip: 'Volgende',
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: <Widget>[
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ColoredBox(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: imageUrl == null
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Text(
                                        (card.title == null || card.title!.trim().isEmpty)
                                            ? '(zonder titel)'
                                            : card.title!.trim(),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  )
                                : Stack(
                                    fit: StackFit.expand,
                                    children: <Widget>[
                                      Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Center(
                                            child: Text('Afbeelding laden mislukt'),
                                          );
                                        },
                                      ),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final ann =
                                              ImageAnnotations.tryParse(card.imageAnnotationsJson);
                                          if (ann == null || ann.items.isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          return CustomPaint(
                                            painter: _ImageAnnotOverlayPainter(items: ann.items),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: <Widget>[
                        IconButton.filledTonal(
                          onPressed: hasPrev ? () => _go(_index - 1) : null,
                          icon: const Icon(Icons.arrow_left),
                          tooltip: 'Vorige',
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _dataUrlCache[card.audioDriveFileId] == null ? null : _togglePlay,
                            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                            label: Text(_isPlaying ? 'Pauze' : 'Geluid afspelen'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          onPressed: hasNext ? () => _go(_index + 1) : null,
                          icon: const Icon(Icons.arrow_right),
                          tooltip: 'Volgende',
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

class _ImageAnnotOverlayPainter extends CustomPainter {
  const _ImageAnnotOverlayPainter({required this.items});

  final List<ImageAnnotationItem> items;

  @override
  void paint(Canvas canvas, Size size) {
    for (final it in items) {
      if (it is ArrowAnnotation) {
        _paintArrow(canvas, size, it);
      } else if (it is TextAnnotation) {
        _paintText(canvas, size, it);
      }
    }
  }

  void _paintArrow(Canvas canvas, Size size, ArrowAnnotation a) {
    final p1 = Offset(a.fromX * size.width, a.fromY * size.height);
    final p2 = Offset(a.toX * size.width, a.toY * size.height);
    final dir = (p2 - p1);
    if (dir.distance < 4) return;

    final u = dir / dir.distance;
    final n = Offset(-u.dy, u.dx);

    final thickness = a.widthRel != null
        ? max(2.0, a.widthRel! * min(size.width, size.height))
        : (a.width <= 0 ? 2.0 : a.width.toDouble());
    final headLen = thickness * 4.0;
    final headWidth = thickness * 3.0;
    final base = p2 - u * headLen;

    final halfShaft = thickness / 2;
    final halfHead = headWidth / 2;

    final shaftLeftStart = p1 + n * halfShaft;
    final shaftRightStart = p1 - n * halfShaft;
    final shaftLeftEnd = base + n * halfShaft;
    final shaftRightEnd = base - n * halfShaft;
    final headLeft = base + n * halfHead;
    final headRight = base - n * halfHead;

    final path = Path()
      ..moveTo(shaftLeftStart.dx, shaftLeftStart.dy)
      ..lineTo(shaftLeftEnd.dx, shaftLeftEnd.dy)
      ..lineTo(headLeft.dx, headLeft.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(headRight.dx, headRight.dy)
      ..lineTo(shaftRightEnd.dx, shaftRightEnd.dy)
      ..lineTo(shaftRightStart.dx, shaftRightStart.dy)
      ..close();

    final fillPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(2.0, thickness * 0.35)
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, outlinePaint);
  }

  void _paintText(Canvas canvas, Size size, TextAnnotation t) {
    final pos = Offset(t.atX * size.width, t.atY * size.height);
    final style = TextStyle(
      color: _parseHex(t.colorHex, fallback: const Color(0xFF000000)),
      fontSize: t.sizeRel != null
          ? max(10.0, t.sizeRel! * min(size.width, size.height))
          : t.size,
      fontWeight: FontWeight.w700,
      shadows: const <Shadow>[Shadow(blurRadius: 2, offset: Offset(0, 1))],
    );
    final painter = TextPainter(
      text: TextSpan(text: t.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: size.width);
    painter.paint(canvas, pos);
  }

  Color _parseHex(String hex, {required Color fallback}) {
    final h = hex.trim();
    if (!h.startsWith('#')) return fallback;
    final raw = h.substring(1);
    final v = int.tryParse(raw, radix: 16);
    if (v == null) return fallback;
    if (raw.length == 6) return Color(0xFF000000 | v);
    if (raw.length == 8) return Color(v);
    return fallback;
  }

  @override
  bool shouldRepaint(covariant _ImageAnnotOverlayPainter oldDelegate) {
    return oldDelegate.items != items;
  }
}

