import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/card_item.dart';
import '../../domain/cards/card_types.dart';
import '../../domain/models/tab_category.dart';
import '../../services/appwrite/teacher_repository.dart';
import '../../services/audio/app_audio_player.dart';
import '../../services/audio/audio_recorder.dart';
import '../../services/appwrite/appwrite_providers.dart';
import '../../services/drive/drive_api.dart';
import '../../services/drive/drive_picker.dart';
import '../../services/web/blob_url.dart';
import '../../domain/models/image_annotation.dart';
import '../../utils/tab_color.dart';
import '../../widgets/tab_color_picker_dialog.dart';
import 'teacher_navigation.dart';
import 'teacher_ranking_results_screen.dart';

class TeacherTabScreen extends ConsumerStatefulWidget {
  const TeacherTabScreen({super.key, required this.userId, required this.tab});

  final String userId;
  final TabCategory tab;

  @override
  ConsumerState<TeacherTabScreen> createState() => _TeacherTabScreenState();
}

/// Same parsing as [CardViewerScreen]: Drive downloads return `data:...;base64,...`
/// which often fails on [html.AudioElement]; blob URLs decode reliably.
({String mimeType, List<int> bytes})? _parseAudioDataUrl(String dataUrl) {
  const prefix = 'data:';
  if (!dataUrl.startsWith(prefix)) return null;
  final comma = dataUrl.indexOf(',');
  if (comma <= 0) return null;
  final meta = dataUrl.substring(prefix.length, comma);
  final isBase64 = meta.endsWith(';base64');
  if (!isBase64) return null;
  final mimeType = meta.substring(0, meta.length - ';base64'.length);
  final b64 = dataUrl.substring(comma + 1);
  try {
    return (
      mimeType: mimeType.isEmpty ? 'application/octet-stream' : mimeType,
      bytes: base64Decode(b64),
    );
  } catch (_) {
    return null;
  }
}

class _TeacherTabScreenState extends ConsumerState<TeacherTabScreen> {
  late TabCategory _tab;
  final AppAudioPlayer _listAudio = AppAudioPlayer.create();
  final BlobUrl _listAudioBlob = BlobUrl.create();
  final Map<String, String> _listAudioObjectUrlsByFileId = <String, String>{};
  StreamSubscription<void>? _audioEndedSub;
  String? _playingCardId;
  bool _listAudioPaused = false;

  bool _cardsLoading = true;
  Object? _cardsLoadError;
  List<CardItem> _cards = <CardItem>[];
  bool _orderSaving = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.tab;
    // ignore: unawaited_futures
    _reloadCards();
    _audioEndedSub = _listAudio.onEnded.listen((_) {
      if (!mounted) return;
      setState(() {
        _playingCardId = null;
        _listAudioPaused = false;
      });
    });
  }

  @override
  void dispose() {
    _audioEndedSub?.cancel();
    // ignore: unawaited_futures
    _listAudio.stop();
    if (kIsWeb) {
      for (final objectUrl in _listAudioObjectUrlsByFileId.values) {
        _listAudioBlob.revokeObjectUrl(objectUrl);
      }
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(TeacherTabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id) {
      _tab = widget.tab;
      // ignore: unawaited_futures
      _reloadCards();
    } else if (oldWidget.tab.title != widget.tab.title ||
        oldWidget.tab.tabColorHex != widget.tab.tabColorHex) {
      _tab = widget.tab;
    }
  }

  Future<void> _reloadCards() async {
    if (!mounted) return;
    setState(() {
      _cardsLoading = true;
      _cardsLoadError = null;
    });
    try {
      final list = await ref.read(teacherRepositoryProvider).listCards(tabId: _tab.id);
      if (!mounted) return;
      setState(() {
        _cards = list;
        _cardsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cardsLoadError = e;
        _cardsLoading = false;
      });
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _cards.length) return;
    if (newIndex < 0 || newIndex > _cards.length) return;
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    setState(() {
      final item = _cards.removeAt(oldIndex);
      _cards.insert(newIndex, item);
      _cards = List<CardItem>.generate(
        _cards.length,
        (i) => _cards[i].copyWith(sortOrder: i),
      );
    });
    // ignore: unawaited_futures
    _persistCardOrder();
  }

  Future<void> _persistCardOrder() async {
    if (!mounted) return;
    setState(() => _orderSaving = true);
    try {
      final repo = ref.read(teacherRepositoryProvider);
      await Future.wait<void>(
        <Future<void>>[
          for (var i = 0; i < _cards.length; i++)
            repo.updateCardSortOrder(cardId: _cards[i].id, sortOrder: i),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Volgorde opslaan mislukt: $e')),
        );
        await _reloadCards();
      }
    } finally {
      if (mounted) setState(() => _orderSaving = false);
    }
  }

  Future<void> _openEditCard(BuildContext context, CardItem card) async {
    final updated = await Navigator.of(context).push<CardItem?>(
      MaterialPageRoute<CardItem?>(
        builder: (_) => _CreateCardScreen(
          userId: widget.userId,
          tabId: _tab.id,
          tabDriveFolderId: _tab.driveFolderId,
          sortOrder: card.sortOrder,
          existing: card,
        ),
      ),
    );
    if (updated == null || !context.mounted) return;
    setState(() {
      final idx = _cards.indexWhere((c) => c.id == updated.id);
      if (idx >= 0) _cards[idx] = updated;
    });
  }

  Future<void> _toggleListAudio(CardItem card) async {
    if (card.audioDriveFileId.trim().isEmpty) return;
    final same = _playingCardId == card.id;
    if (same && _listAudio.isPlaying) {
      await _listAudio.pause();
      if (mounted) setState(() => _listAudioPaused = true);
      return;
    }
    if (same && _listAudioPaused) {
      await _listAudio.play();
      if (mounted) setState(() => _listAudioPaused = false);
      return;
    }
    await _listAudio.stop();
    if (!mounted) return;
    setState(() {
      _playingCardId = card.id;
      _listAudioPaused = false;
    });
    try {
      final drive = ref.read(driveApiProvider);
      final url = await drive.downloadDataUrl(fileId: card.audioDriveFileId);
      if (!mounted) return;

      var urlToPlay = url;
      if (kIsWeb && url.startsWith('data:')) {
        final cached = _listAudioObjectUrlsByFileId[card.audioDriveFileId];
        if (cached != null) {
          urlToPlay = cached;
        } else {
          final parsed = _parseAudioDataUrl(url);
          if (parsed != null) {
            final fromCard = card.audioMimeType.split(';').first.trim();
            final fromData = parsed.mimeType.split(';').first.trim();
            final mimeForPlay =
                fromCard.startsWith('audio/') ? fromCard : fromData;
            urlToPlay = _listAudioBlob.createObjectUrl(
              bytes: parsed.bytes,
              mimeType: mimeForPlay,
            );
            _listAudioObjectUrlsByFileId[card.audioDriveFileId] = urlToPlay;
          }
        }
      }

      await _listAudio.load(urlToPlay);
      await _listAudio.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playingCardId = null;
        _listAudioPaused = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audio afspelen mislukt: $e')),
      );
    }
  }

  Future<String?> _promptTabTitle(
    BuildContext context, {
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tabblad hernoemen'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Titel tabblad',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Opslaan'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final t = result?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<void> _renameThisTab(BuildContext context) async {
    final title = await _promptTabTitle(context, initial: _tab.title);
    if (title == null) return;
    try {
      final updated =
          await ref.read(teacherRepositoryProvider).updateTabTitle(tabId: _tab.id, title: title);
      if (!context.mounted) return;
      setState(() => _tab = updated);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tabblad hernoemen mislukt: $e')),
      );
    }
  }

  Future<void> _pickTabColor(BuildContext context) async {
    final String? picked =
        await showTabColorPickerDialog(context, currentHex: _tab.tabColorHex);
    if (picked == null || !context.mounted) return;
    try {
      final TabCategory updated = await ref.read(teacherRepositoryProvider).updateTabColor(
            tabId: _tab.id,
            tabColorHex: picked.isEmpty ? null : picked,
          );
      if (!context.mounted) return;
      setState(() => _tab = updated);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tabbladkleur bijwerken mislukt: $e')),
      );
    }
  }

  Future<void> _deleteThisTab(BuildContext context) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Tabblad verwijderen?'),
            content: Text(
              'Verwijdert „${_tab.title}” en alle bijbehorende kaarten. Drive-bestanden blijven staan.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuleren'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Verwijderen'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await ref.read(teacherRepositoryProvider).deleteTabCascade(tabId: _tab.id);
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tabblad verwijderen mislukt: $e')),
      );
    }
  }

  Future<void> _confirmDeleteCard(CardItem card) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kaart verwijderen?'),
            content: Text(
              card.title == null || card.title!.isEmpty
                  ? 'Deze kaart verwijderen? Drive-bestanden worden niet gewist.'
                  : '„${card.title}” verwijderen? Drive-bestanden worden niet gewist.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuleren'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Verwijderen'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      if (_playingCardId == card.id) {
        await _listAudio.stop();
        _playingCardId = null;
        _listAudioPaused = false;
      }
      final folderId = card.driveFolderId?.trim();
      if (folderId != null && folderId.isNotEmpty) {
        final drive = ref.read(driveApiProvider);
        await drive.trashAndLog(
          fileId: folderId,
          name: card.title ?? 'Kaart',
          kind: 'card-folder',
        );
      }
      await ref.read(teacherRepositoryProvider).deleteCard(cardId: card.id);
      if (!mounted) return;
      _listAudioObjectUrlsByFileId.remove(card.audioDriveFileId);
      await _reloadCards();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaart verwijderen mislukt: $e')),
      );
    }
  }

  List<Widget> _tabAppBarActions(BuildContext context) {
    final Color? accent = parseTabColorHex(_tab.tabColorHex);
    final Color? classesBtnColor =
        accent != null ? foregroundOnTabColor(accent) : null;
    return <Widget>[
      Tooltip(
        message: 'Startpagina Lerarenhulp — leerlingtoegang, leraar inloggen',
        child: TextButton.icon(
          onPressed: () => goToTeachersHelpStart(context),
          icon: const Icon(Icons.home_rounded),
          label: const Text('Startpagina'),
          style: classesBtnColor != null
              ? TextButton.styleFrom(foregroundColor: classesBtnColor)
              : null,
        ),
      ),
      Tooltip(
        message:
            'Terug naar je klassen — open daar de leerlinglink om de klas te proberen',
        child: TextButton.icon(
          onPressed: () => popToTeacherClassList(context),
          icon: const Icon(Icons.grid_view_rounded),
          label: const Text('Klassen'),
          style: classesBtnColor != null
              ? TextButton.styleFrom(foregroundColor: classesBtnColor)
              : null,
        ),
      ),
      if (_tab.isRanking)
        IconButton(
          tooltip: 'Resultaten',
          icon: const Icon(Icons.bar_chart),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TeacherRankingResultsScreen(
                userId: widget.userId,
                tab: _tab,
              ),
            ),
          ),
        ),
      PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'color') {
            await _pickTabColor(context);
          } else if (value == 'rename') {
            await _renameThisTab(context);
          } else if (value == 'delete') {
            await _deleteThisTab(context);
          }
        },
        itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'color',
            child: Text('Tabbladkleur'),
          ),
          const PopupMenuItem<String>(
            value: 'rename',
            child: Text('Tabblad hernoemen'),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            child: Text(
              'Tabblad verwijderen',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_cardsLoading) {
      return Scaffold(
        appBar: buildTabColoredAppBar(
          context,
          title: _tab.title,
          tabColorHex: _tab.tabColorHex,
          actions: _tabAppBarActions(context),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_cardsLoadError != null) {
      return Scaffold(
        appBar: buildTabColoredAppBar(
          context,
          title: _tab.title,
          tabColorHex: _tab.tabColorHex,
          actions: _tabAppBarActions(context),
        ),
        body: Center(child: Text('Fout: $_cardsLoadError')),
      );
    }

    return Scaffold(
      appBar: buildTabColoredAppBar(
        context,
        title: _tab.title,
        tabColorHex: _tab.tabColorHex,
        actions: _tabAppBarActions(context),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Kaarten',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _orderSaving
                          ? null
                          : () async {
                              final created = await Navigator.of(context).push<CardItem?>(
                                MaterialPageRoute<CardItem?>(
                                  builder: (_) => _CreateCardScreen(
                                    userId: widget.userId,
                                    tabId: _tab.id,
                                    tabDriveFolderId: _tab.driveFolderId,
                                    sortOrder: _cards.length,
                                  ),
                                ),
                              );
                              if (created == null) return;
                              if (!context.mounted) return;
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) => TeacherTabScreen(userId: widget.userId, tab: _tab),
                                ),
                              );
                            },
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('Kaart toevoegen'),
                    ),
                  ],
                ),
                if (_cards.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Sleep om de volgorde te wijzigen (ook zichtbaar voor leerlingen).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (_orderSaving) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _cards.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Nog geen kaarten. Voeg je eerste afbeelding + audio toe.'),
                  )
                : AbsorbPointer(
                    absorbing: _orderSaving,
                    child: ReorderableListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      onReorder: _onReorder,
                      children: <Widget>[
                        for (var i = 0; i < _cards.length; i++)
                          ReorderableDragStartListener(
                            index: i,
                            key: ValueKey<String>(_cards[i].id),
                            child: _TeacherCardRow(
                              card: _cards[i],
                              isPlayingAudio: _playingCardId == _cards[i].id &&
                                  (_listAudio.isPlaying || _listAudioPaused),
                              audioIsPaused: _playingCardId == _cards[i].id && _listAudioPaused,
                              onAudioToggle: () => _toggleListAudio(_cards[i]),
                              onEdit: _orderSaving
                                  ? null
                                  : () => _openEditCard(context, _cards[i]),
                              onDelete: _orderSaving
                                  ? null
                                  : () => _confirmDeleteCard(_cards[i]),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TeacherCardRow extends ConsumerStatefulWidget {
  const _TeacherCardRow({
    required this.card,
    required this.isPlayingAudio,
    required this.audioIsPaused,
    required this.onAudioToggle,
    this.onEdit,
    this.onDelete,
  });

  final CardItem card;
  final bool isPlayingAudio;
  final bool audioIsPaused;
  final VoidCallback onAudioToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  ConsumerState<_TeacherCardRow> createState() => _TeacherCardRowState();
}

class _TeacherCardRowState extends ConsumerState<_TeacherCardRow> {
  String? _imageDataUrl;
  Object? _imageError;
  bool _imageLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _TeacherCardRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.imageDriveFileId != widget.card.imageDriveFileId) {
      setState(() {
        _imageLoading = true;
        _imageError = null;
        _imageDataUrl = null;
      });
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.card.imageDriveFileId.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _imageDataUrl = null;
        _imageError = null;
        _imageLoading = false;
      });
      return;
    }
    try {
      final drive = ref.read(driveApiProvider);
      final url = await drive.downloadDataUrl(fileId: widget.card.imageDriveFileId);
      if (!mounted) return;
      setState(() {
        _imageDataUrl = url;
        _imageLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imageError = e;
        _imageLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget leading;
    if (_imageLoading) {
      leading = const SizedBox(
        width: 72,
        height: 72,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (_imageError != null) {
      leading = SizedBox(
        width: 72,
        height: 72,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      );
    } else if (_imageDataUrl == null) {
      leading = SizedBox(
        width: 72,
        height: 72,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              (widget.card.title == null || widget.card.title!.trim().isEmpty)
                  ? '(zonder titel)'
                  : widget.card.title!.trim(),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      );
    } else {
      leading = SizedBox(
        width: 72,
        height: 72,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Image.network(
              _imageDataUrl!,
              fit: BoxFit.cover,
              width: 72,
              height: 72,
              errorBuilder: (context, error, stackTrace) {
                return const Center(child: Icon(Icons.broken_image_outlined));
              },
            ),
          ),
        ),
      );
    }

    final bool showPause = widget.isPlayingAudio && !widget.audioIsPaused;
    final bool hasAudio = widget.card.audioDriveFileId.trim().isNotEmpty;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: leading,
      title: Text(widget.card.title ?? '(zonder titel)'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton.filledTonal(
            onPressed: widget.onEdit,
            tooltip: 'Kaart bewerken',
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton.filledTonal(
            onPressed: widget.onDelete,
            tooltip: 'Kaart verwijderen',
            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
          ),
          IconButton.filledTonal(
            onPressed: hasAudio ? widget.onAudioToggle : null,
            tooltip: !hasAudio ? 'Geen audio' : (showPause ? 'Pauze' : 'Audio-voorbeeld afspelen'),
            icon: Icon(showPause ? Icons.pause : Icons.play_arrow),
          ),
          Icon(
            Icons.drag_handle,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _CreateCardScreen extends ConsumerStatefulWidget {
  const _CreateCardScreen({
    required this.userId,
    required this.tabId,
    required this.tabDriveFolderId,
    required this.sortOrder,
    this.existing,
  });

  final String userId;
  final String tabId;
  final String? tabDriveFolderId;
  final int sortOrder;
  final CardItem? existing;

  @override
  ConsumerState<_CreateCardScreen> createState() => _CreateCardScreenState();
}

class _CreateCardScreenState extends ConsumerState<_CreateCardScreen> {
  final TextEditingController _title = TextEditingController();
  String _cardType = CardTypeIds.soundImage;
  final TextEditingController _fillPrompt = TextEditingController();
  final TextEditingController _fillAnswers = TextEditingController();
  final Random _rng = Random.secure();
  Uint8List? _imageBytes;
  String? _imageMime;
  String? _imageName;
  String? _imageDriveFileId;
  String? _imagePreviewUrl;
  bool _imagePreviewLoading = false;
  Object? _imagePreviewError;
  Size? _imagePixelSize;
  Rect? _lastImageRect;
  ImageStream? _imageSizeStream;
  ImageStreamListener? _imageSizeListener;

  // Image annotation editor state (stored as JSON on the card).
  final List<ImageAnnotationItem> _imageAnnotations = <ImageAnnotationItem>[];
  _ImageAnnotTool _annotTool = _ImageAnnotTool.arrow;
  ({double x, double y})? _arrowFrom;
  ({double x, double y})? _arrowTo;
  int? _selectedAnnotIndex;
  _ArrowDragTarget? _arrowDragTarget;
  Offset? _moveLastPosPx;

  Uint8List? _audioBytes;
  String? _audioMime;
  String? _audioName;
  String? _audioDriveFileId;
  String? _audioPreviewObjectUrl;
  bool _audioDrivePreviewLoading = false;

  bool _saving = false;
  bool _recordStarting = false;
  bool _recording = false;
  final AudioRecorder _recorder = AudioRecorder.create();
  final AppAudioPlayer _player = AppAudioPlayer.create();
  final BlobUrl _blobUrl = BlobUrl.create();
  bool _isPreviewPlaying = false;
  final DrivePickerService _drivePicker = DrivePickerService.create();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _title.text = existing.title ?? '';
      _cardType = CardTypeRegistry.normalizeType(existing.cardType);
      if (_cardType == CardTypeIds.imageFillIn) {
        final decoded = ImageFillInCardData.tryDecode(existing.cardDataJson);
        _fillPrompt.text = decoded?.prompt ?? '';
        _fillAnswers.text = (decoded?.acceptedAnswers ?? const <String>[]).join(', ');
      }
      if (existing.imageDriveFileId.trim().isNotEmpty) {
        _imageDriveFileId = existing.imageDriveFileId;
        _imageMime = existing.imageMimeType;
        _imageName = 'Huidige afbeelding';
        // ignore: unawaited_futures
        _primeExistingImagePreview();
      }
      final ann = ImageAnnotations.tryParse(existing.imageAnnotationsJson);
      if (ann != null) {
        _imageAnnotations
          ..clear()
          ..addAll(ann.items);
      }
      if (existing.audioDriveFileId.trim().isNotEmpty) {
        _audioDriveFileId = existing.audioDriveFileId;
        _audioMime = existing.audioMimeType;
        _audioName = 'Huidige audio';
        // ignore: unawaited_futures
        _primeExistingAudioPreview();
      }
    }
  }

  Future<void> _primeExistingImagePreview() async {
    if (_imageDriveFileId == null || _imageDriveFileId!.trim().isEmpty) return;
    setState(() {
      _imagePreviewLoading = true;
      _imagePreviewError = null;
      _imagePreviewUrl = null;
      _imagePixelSize = null;
    });
    try {
      final drive = ref.read(driveApiProvider);
      final url = await drive.downloadDataUrl(fileId: _imageDriveFileId!);
      if (!mounted) return;
      setState(() {
        _imagePreviewUrl = url;
        _imagePreviewLoading = false;
      });
      _listenImagePixelSize();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imagePreviewError = e;
        _imagePreviewLoading = false;
      });
    }
  }

  Future<void> _primeExistingAudioPreview() async {
    if (!kIsWeb) return;
    final existing = widget.existing;
    if (existing == null) return;
    if (existing.audioDriveFileId.trim().isEmpty) return;
    setState(() => _audioDrivePreviewLoading = true);
    try {
      final drive = ref.read(driveApiProvider);
      final downloaded = await drive.downloadBytes(fileId: existing.audioDriveFileId);
      if (!mounted) return;
      final mimeForPreview = _normalizeAudioMime(
        name: _audioName,
        mimeType: downloaded.mimeType,
      );
      _setPreviewObjectUrl(bytes: downloaded.bytes, mimeType: mimeForPreview);
      setState(() {
        _audioMime = mimeForPreview;
        _audioDrivePreviewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _audioDrivePreviewLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audio voor voorbeeld laden mislukt: $e')),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _fillPrompt.dispose();
    _fillAnswers.dispose();
    _player.stop();
    _stopListeningImagePixelSize();
    // Best-effort cleanup to release the microphone if it was opened.
    // ignore: unawaited_futures
    _recorder.dispose();
    final url = _audioPreviewObjectUrl;
    if (url != null && kIsWeb) _blobUrl.revokeObjectUrl(url);
    super.dispose();
  }

  String? get _effectivePreviewUrl => _audioPreviewObjectUrl;

  void _stopListeningImagePixelSize() {
    final stream = _imageSizeStream;
    final listener = _imageSizeListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageSizeStream = null;
    _imageSizeListener = null;
  }

  void _listenImagePixelSize() {
    final url = _imagePreviewUrl;
    if (url == null || url.trim().isEmpty) return;

    _stopListeningImagePixelSize();
    final provider = NetworkImage(url);
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final img = info.image;
        final next = Size(img.width.toDouble(), img.height.toDouble());
        if (!mounted) return;
        setState(() => _imagePixelSize = next);
        _stopListeningImagePixelSize();
      },
      onError: (_, __) {
        // Best effort: drawing still works without the exact rect.
        _stopListeningImagePixelSize();
      },
    );
    _imageSizeStream = stream;
    _imageSizeListener = listener;
    stream.addListener(listener);
  }

  Rect _imageRectForContainer(Size container) {
    final px = _imagePixelSize;
    if (px == null || px.width <= 0 || px.height <= 0) {
      return Offset.zero & container;
    }
    final fitted = applyBoxFit(BoxFit.contain, px, container);
    final dst = fitted.destination;
    final left = (container.width - dst.width) / 2;
    final top = (container.height - dst.height) / 2;
    return Rect.fromLTWH(left, top, dst.width, dst.height);
  }

  double _minSide(Rect r) => min(r.width, r.height);

  double _arrowWidthPx(ArrowAnnotation a, Rect imageRect) {
    final rel = a.widthRel;
    if (rel != null) return max(2.0, rel * _minSide(imageRect));
    return max(2.0, a.width);
  }

  double _textSizePx(TextAnnotation t, Rect imageRect) {
    final rel = t.sizeRel;
    if (rel != null) return max(10.0, rel * _minSide(imageRect));
    return max(10.0, t.size);
  }

  String _normalizeAudioMime({required String? name, required String mimeType}) {
    final raw = mimeType.trim();
    final mt = raw.split(';').first.trim(); // strip params like charset/codecs
    if (mt.startsWith('audio/')) return mt;
    final lower = (name ?? '').toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.webm')) return 'audio/webm';
    return mt.isEmpty ? 'application/octet-stream' : mt;
  }

  String _sanitizeForDriveFilename(String input) {
    final s = input.trim();
    if (s.isEmpty) return 'audio';
    final replaced = s.replaceAll(RegExp(r'\s+'), '_');
    final cleaned = replaced.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '');
    final collapsed = cleaned.replaceAll(RegExp(r'_+'), '_');
    final out = collapsed.isEmpty ? 'audio' : collapsed;
    return out.length <= 80 ? out : out.substring(0, 80);
  }

  String _shortId() {
    const alphabet = '23456789abcdefghjkmnpqrstuvwxyz'; // avoid confusing chars
    final buf = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buf.write(alphabet[_rng.nextInt(alphabet.length)]);
    }
    return buf.toString();
  }

  String _audioExt({required String? name, required String? mimeType}) {
    final n = (name ?? '').toLowerCase();
    if (n.endsWith('.mp3')) return '.mp3';
    if (n.endsWith('.wav')) return '.wav';
    if (n.endsWith('.m4a')) return '.m4a';
    if (n.endsWith('.aac')) return '.aac';
    if (n.endsWith('.ogg')) return '.ogg';
    if (n.endsWith('.webm')) return '.webm';

    final mt = (mimeType ?? '').split(';').first.trim().toLowerCase();
    if (mt == 'audio/mpeg') return '.mp3';
    if (mt == 'audio/wav') return '.wav';
    if (mt == 'audio/mp4') return '.m4a';
    if (mt == 'audio/aac') return '.aac';
    if (mt == 'audio/ogg') return '.ogg';
    if (mt == 'audio/webm') return '.webm';
    return '.wav';
  }

  void _stopPreview() {
    _player.stop();
    if (mounted) setState(() => _isPreviewPlaying = false);
  }

  void _setPreviewObjectUrl({required List<int> bytes, required String mimeType}) {
    if (!kIsWeb) return;
    final old = _audioPreviewObjectUrl;
    if (old != null) _blobUrl.revokeObjectUrl(old);
    final normalized = _normalizeAudioMime(name: _audioName, mimeType: mimeType);
    _audioPreviewObjectUrl = _blobUrl.createObjectUrl(bytes: bytes, mimeType: normalized);
  }

  Future<void> _togglePreviewPlay() async {
    if (!kIsWeb) return;
    if (_recordStarting || _recording || _saving) return;
    final url = _effectivePreviewUrl;
    if (url == null) return;

    if (_isPreviewPlaying) {
      await _player.pause();
      if (!mounted) return;
      setState(() => _isPreviewPlaying = false);
      return;
    }

    try {
      await _player.load(url);
      await _player.play();
      if (!mounted) return;
      setState(() => _isPreviewPlaying = true);
      _player.onEnded.listen((_) {
        if (!mounted) return;
        setState(() => _isPreviewPlaying = false);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Afspelen van audio mislukt: $e')),
      );
    }
  }

  Future<void> _pickImageFromDrive() async {
    if (!kIsWeb) return;
    final config = ref.read(appConfigProvider);
    final drive = ref.read(driveApiProvider);
    final token = await drive.getAccessToken();
    final picked = await _drivePicker.pick(
      googleApiKey: config.googleApiKey,
      oauthAccessToken: token,
      isImage: true,
    );
    if (picked == null) return;
    setState(() {
      _imageDriveFileId = picked.id;
      _imageName = picked.name;
      _imageMime = picked.mimeType;
      _imageBytes = null;
      _imagePreviewLoading = true;
      _imagePreviewError = null;
      _imagePreviewUrl = null;
      _imageAnnotations.clear();
      _arrowFrom = null;
      _arrowTo = null;
    });
    try {
      final url = await drive.downloadDataUrl(fileId: picked.id);
      if (!mounted) return;
      setState(() {
        _imagePreviewUrl = url;
        _imagePreviewLoading = false;
      });
      _listenImagePixelSize();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imagePreviewError = e;
        _imagePreviewLoading = false;
      });
    }
  }

  Future<void> _pickAudioFromDrive() async {
    if (!kIsWeb) return;
    final config = ref.read(appConfigProvider);
    final drive = ref.read(driveApiProvider);
    final token = await drive.getAccessToken();
    final picked = await _drivePicker.pick(
      googleApiKey: config.googleApiKey,
      oauthAccessToken: token,
      isImage: false,
    );
    if (picked == null) return;
    _stopPreview();
    setState(() {
      _audioDriveFileId = picked.id;
      _audioName = picked.name;
      _audioMime = picked.mimeType;
      _audioBytes = null;
      _audioDrivePreviewLoading = true;
    });

    try {
      final downloaded = await drive.downloadBytes(fileId: picked.id);
      if (!mounted) return;
      final mimeForPreview = _normalizeAudioMime(
        name: picked.name,
        mimeType: downloaded.mimeType,
      );
      _setPreviewObjectUrl(bytes: downloaded.bytes, mimeType: mimeForPreview);
      setState(() {
        // Keep the picker MIME if Drive returns application/octet-stream.
        _audioMime = mimeForPreview;
        _audioDrivePreviewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _audioDrivePreviewLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voorbeeld downloaden mislukt: $e')),
      );
    }
  }

  Future<void> _toggleRecord() async {
    if (!kIsWeb) return;
    if (_saving) return;
    if (_recordStarting) return;
    if (_recording) {
      final rec = await _recorder.stop();
      if (!mounted) return;
      if (rec.bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opname was leeg. Probeer het opnieuw.')),
        );
        setState(() => _recording = false);
        return;
      }

      final normalized = _normalizeAudioMime(
        name: _audioName ?? 'recording.wav',
        mimeType: rec.mimeType,
      );
      _setPreviewObjectUrl(bytes: rec.bytes, mimeType: normalized);
      setState(() {
        _recording = false;
        _audioBytes = Uint8List.fromList(rec.bytes);
        _audioMime = normalized;
        _audioName = 'recording_${DateTime.now().millisecondsSinceEpoch}.wav';
        _audioDriveFileId = null;
      });
      return;
    }

    try {
      _stopPreview();
      setState(() => _recordStarting = true);
      await _recorder.start();
      if (!mounted) return;
      setState(() {
        _recordStarting = false;
        _recording = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _recordStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opnemen mislukt: $e')),
      );
    }
  }

  Future<String?> _promptText(
    BuildContext context, {
    required String dialogTitle,
    required String confirmLabel,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Tekst',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final t = result?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  void _clearAnnotations() {
    setState(() {
      _imageAnnotations.clear();
      _arrowFrom = null;
      _arrowTo = null;
      _selectedAnnotIndex = null;
      _arrowDragTarget = null;
      _moveLastPosPx = null;
      _lastImageRect = null;
    });
  }

  Offset _toPx({required Rect imageRect, required double x01, required double y01}) {
    return Offset(imageRect.left + x01 * imageRect.width, imageRect.top + y01 * imageRect.height);
  }

  ({double x, double y}) _to01({required Rect imageRect, required Offset localPos}) {
    final x = ((localPos.dx - imageRect.left) / imageRect.width).clamp(0.0, 1.0);
    final y = ((localPos.dy - imageRect.top) / imageRect.height).clamp(0.0, 1.0);
    return (x: x, y: y);
  }

  double _distPointToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (ab2 <= 0.000001) return (p - a).distance;
    var t = (ap.dx * ab.dx + ap.dy * ab.dy) / ab2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  int? _hitTestAnnotIndex({required Offset localPos, required Rect imageRect}) {
    // Iterate from end so the last added item wins (top-most).
    for (var i = _imageAnnotations.length - 1; i >= 0; i--) {
      final it = _imageAnnotations[i];
      if (it is TextAnnotation) {
        final pos = _toPx(imageRect: imageRect, x01: it.atX, y01: it.atY);
        final style = TextStyle(
          color: Colors.black,
          fontSize: _textSizePx(it, imageRect),
          fontWeight: FontWeight.w700,
          shadows: const <Shadow>[Shadow(blurRadius: 2, offset: Offset(0, 1))],
        );
        final painter = TextPainter(
          text: TextSpan(text: it.text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 3,
          ellipsis: '…',
        )..layout(maxWidth: imageRect.width);
        final rect = Rect.fromLTWH(pos.dx, pos.dy, painter.width, painter.height).inflate(10);
        if (rect.contains(localPos)) return i;
      } else if (it is ArrowAnnotation) {
        final p1 = _toPx(imageRect: imageRect, x01: it.fromX, y01: it.fromY);
        final p2 = _toPx(imageRect: imageRect, x01: it.toX, y01: it.toY);
        final thickness = _arrowWidthPx(it, imageRect);
        final hitPad = max(32.0, thickness * 3.0);
        final d = _distPointToSegment(localPos, p1, p2);
        if (d <= hitPad) return i;
      }
    }
    return null;
  }

  _ArrowDragTarget? _hitTestArrowDragTarget({
    required Offset localPos,
    required Rect imageRect,
    required ArrowAnnotation a,
  }) {
    final p1 = _toPx(imageRect: imageRect, x01: a.fromX, y01: a.fromY);
    final p2 = _toPx(imageRect: imageRect, x01: a.toX, y01: a.toY);
    final thickness = _arrowWidthPx(a, imageRect);
    final handleR = max(34.0, thickness * 2.5);
    if ((localPos - p1).distance <= handleR) return _ArrowDragTarget.from;
    if ((localPos - p2).distance <= handleR) return _ArrowDragTarget.to;
    final d = _distPointToSegment(localPos, p1, p2);
    final hitPad = max(32.0, thickness * 3.0);
    if (d <= hitPad) return _ArrowDragTarget.whole;
    return null;
  }

  void _onAnnotTap({required Offset localPos, required Rect imageRect}) async {
    if (!mounted) return;
    if (imageRect.width <= 0 || imageRect.height <= 0) return;
    if (!imageRect.contains(localPos)) return;
    final pos = _to01(imageRect: imageRect, localPos: localPos);
    if (_annotTool == _ImageAnnotTool.text) {
      final text = await _promptText(
        context,
        dialogTitle: 'Tekst toevoegen',
        confirmLabel: 'Toevoegen',
      );
      if (text == null || !mounted) return;
      setState(() {
        final rel = 28.0 / _minSide(imageRect);
        _imageAnnotations.add(
          TextAnnotation(
            atX: pos.x,
            atY: pos.y,
            text: text,
            colorHex: '#000000',
            size: 28,
            sizeRel: rel.isFinite && rel > 0 ? rel : null,
          ),
        );
      });
    } else if (_annotTool == _ImageAnnotTool.move) {
      final hit = _hitTestAnnotIndex(localPos: localPos, imageRect: imageRect);
      final selectedBefore = _selectedAnnotIndex;
      if (hit != null &&
          hit == selectedBefore &&
          _imageAnnotations[hit] is TextAnnotation) {
        final it = _imageAnnotations[hit] as TextAnnotation;
        final updated = await _promptText(
          context,
          dialogTitle: 'Tekst bewerken',
          confirmLabel: 'Opslaan',
          initial: it.text,
        );
        if (updated == null || !mounted) return;
        setState(() {
          _imageAnnotations[hit] = TextAnnotation(
            atX: it.atX,
            atY: it.atY,
            text: updated,
            colorHex: it.colorHex,
            size: it.size,
            sizeRel: it.sizeRel,
          );
        });
        return;
      }
      _ArrowDragTarget? target;
      if (hit != null && _imageAnnotations[hit] is ArrowAnnotation) {
        final t = _hitTestArrowDragTarget(
          localPos: localPos,
          imageRect: imageRect,
          a: _imageAnnotations[hit] as ArrowAnnotation,
        );
        // Only "activate" an endpoint when the user tapped the endpoint circle.
        target = (t == _ArrowDragTarget.from || t == _ArrowDragTarget.to) ? t : null;
      }
      setState(() {
        _selectedAnnotIndex = hit;
        _arrowDragTarget = target;
      });
    }
  }

  void _onAnnotPanStart({required Offset localPos, required Rect imageRect}) {
    if (imageRect.width <= 0 || imageRect.height <= 0) return;
    if (!imageRect.contains(localPos)) return;
    if (_annotTool == _ImageAnnotTool.arrow) {
      final pos = _to01(imageRect: imageRect, localPos: localPos);
      setState(() {
        _arrowFrom = (x: pos.x, y: pos.y);
        _arrowTo = (x: pos.x, y: pos.y);
        _selectedAnnotIndex = null;
        _arrowDragTarget = null;
        _moveLastPosPx = null;
      });
      return;
    }
    if (_annotTool == _ImageAnnotTool.move) {
      final idx = _hitTestAnnotIndex(localPos: localPos, imageRect: imageRect);
      _ArrowDragTarget? target;
      if (idx != null && _imageAnnotations[idx] is ArrowAnnotation) {
        target = _hitTestArrowDragTarget(
          localPos: localPos,
          imageRect: imageRect,
          a: _imageAnnotations[idx] as ArrowAnnotation,
        );
      }
      setState(() {
        _selectedAnnotIndex = idx;
        _arrowDragTarget = target;
        _moveLastPosPx = localPos;
      });
    }
  }

  void _onAnnotPanUpdate({required Offset localPos, required Rect imageRect}) {
    if (imageRect.width <= 0 || imageRect.height <= 0) return;
    if (!imageRect.contains(localPos)) return;
    if (_annotTool == _ImageAnnotTool.arrow) {
      if (_arrowFrom == null) return;
      final pos = _to01(imageRect: imageRect, localPos: localPos);
      setState(() => _arrowTo = (x: pos.x, y: pos.y));
      return;
    }
    if (_annotTool != _ImageAnnotTool.move) return;
    final idx = _selectedAnnotIndex;
    final last = _moveLastPosPx;
    if (idx == null || last == null) return;
    final dx01 = (localPos.dx - last.dx) / imageRect.width;
    final dy01 = (localPos.dy - last.dy) / imageRect.height;
    if (dx01.abs() < 0.000001 && dy01.abs() < 0.000001) return;

    final it = _imageAnnotations[idx];
    if (it is TextAnnotation) {
      setState(() {
        _imageAnnotations[idx] = TextAnnotation(
          atX: (it.atX + dx01).clamp(0.0, 1.0),
          atY: (it.atY + dy01).clamp(0.0, 1.0),
          text: it.text,
          colorHex: it.colorHex,
          size: it.size,
          sizeRel: it.sizeRel,
        );
        _moveLastPosPx = localPos;
      });
      return;
    }
    if (it is ArrowAnnotation) {
      final target = _arrowDragTarget ?? _ArrowDragTarget.whole;
      setState(() {
        ArrowAnnotation next;
        if (target == _ArrowDragTarget.from) {
          next = ArrowAnnotation(
            fromX: (it.fromX + dx01).clamp(0.0, 1.0),
            fromY: (it.fromY + dy01).clamp(0.0, 1.0),
            toX: it.toX,
            toY: it.toY,
            colorHex: it.colorHex,
            width: it.width,
            widthRel: it.widthRel,
          );
        } else if (target == _ArrowDragTarget.to) {
          next = ArrowAnnotation(
            fromX: it.fromX,
            fromY: it.fromY,
            toX: (it.toX + dx01).clamp(0.0, 1.0),
            toY: (it.toY + dy01).clamp(0.0, 1.0),
            colorHex: it.colorHex,
            width: it.width,
            widthRel: it.widthRel,
          );
        } else {
          final nFromX = (it.fromX + dx01).clamp(0.0, 1.0);
          final nFromY = (it.fromY + dy01).clamp(0.0, 1.0);
          final nToX = (it.toX + dx01).clamp(0.0, 1.0);
          final nToY = (it.toY + dy01).clamp(0.0, 1.0);
          next = ArrowAnnotation(
            fromX: nFromX,
            fromY: nFromY,
            toX: nToX,
            toY: nToY,
            colorHex: it.colorHex,
            width: it.width,
            widthRel: it.widthRel,
          );
        }
        _imageAnnotations[idx] = next;
        _moveLastPosPx = localPos;
      });
    }
  }

  void _onAnnotPanEnd() {
    if (_annotTool != _ImageAnnotTool.arrow) return;
    final from = _arrowFrom;
    final to = _arrowTo;
    if (from == null || to == null) return;
    setState(() {
      // Store responsive width for new arrows; keep legacy `width` too (Option A).
      final rect = _lastImageRect;
      final rel = rect == null ? null : (6.0 / max(1.0, _minSide(rect)));
      _imageAnnotations.add(
        ArrowAnnotation(
          fromX: from.x,
          fromY: from.y,
          toX: to.x,
          toY: to.y,
          colorHex: '#FF0000',
          width: 6,
          widthRel: (rel != null && rel.isFinite && rel > 0) ? rel : null,
        ),
      );
      _arrowFrom = null;
      _arrowTo = null;
      _selectedAnnotIndex = _imageAnnotations.length - 1;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    _stopPreview();
    final hasImage = (_imageDriveFileId != null) || (_imageBytes != null);
    final hasAudio = (_audioDriveFileId != null) || (_audioBytes != null);
    if (_cardType == CardTypeIds.ranking && !hasImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies een afbeelding.')),
      );
      return;
    }
    if (_cardType == CardTypeIds.imageFillIn && !hasImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies een afbeelding.')),
      );
      return;
    }
    if (_cardType == CardTypeIds.soundImage && !hasImage && !hasAudio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies een afbeelding of audio (minstens één).')),
      );
      return;
    }
    if (hasImage && (_imageMime == null || _imageName == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Afbeelding is incompleet. Kies opnieuw.')),
      );
      return;
    }
    if (_cardType == CardTypeIds.soundImage && hasAudio && (_audioMime == null || _audioName == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio is incompleet. Kies/Neem opnieuw.')),
      );
      return;
    }

    final String titleText = (_cardType == CardTypeIds.ranking)
        ? 'Ranking'
        : _title.text.trim();
    if (_cardType != CardTypeIds.ranking && titleText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Titel is verplicht.')),
      );
      return;
    }

    String? cardDataJson;
    if (_cardType == CardTypeIds.imageFillIn) {
      final prompt = _fillPrompt.text.trim();
      final answers = parseAcceptedAnswersCsv(_fillAnswers.text);
      if (prompt.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schrijf een zin/vraag, bijv. "Dit is een ...?"')),
        );
        return;
      }
      if (answers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vul minstens één goed antwoord in.')),
        );
        return;
      }
      cardDataJson = ImageFillInCardData(prompt: prompt, acceptedAnswers: answers).encode();
    }

    setState(() => _saving = true);
    try {
      final drive = ref.read(driveApiProvider);
      final repo = ref.read(teacherRepositoryProvider);

      String? cardFolderId = widget.existing?.driveFolderId?.trim();
      if (cardFolderId != null && cardFolderId.isEmpty) cardFolderId = null;

      // Best effort: create/ensure a per-card folder under the current tab folder.
      if (cardFolderId == null) {
        try {
          final tabFolderId = widget.tabDriveFolderId?.trim();
          if (tabFolderId != null && tabFolderId.isNotEmpty) {
            final cardsFolder = await drive.ensureFolder(parentId: tabFolderId, name: 'Kaarten');
            final cardFolderName = '${_sanitizeForDriveFilename(titleText)}-${_shortId()}';
            cardFolderId = await drive.ensureFolder(parentId: cardsFolder, name: cardFolderName);
          }
        } catch (_) {
          cardFolderId = null;
        }
      }

      // Fallback: if we couldn't create the card folder, upload into a generic Uploads folder (old behavior).
      List<String>? parents;
      if (cardFolderId != null && cardFolderId.isNotEmpty) {
        parents = <String>[cardFolderId];
      } else {
        try {
          final root = await drive.getRootFolderId();
          if (root.trim().isNotEmpty) {
            final appFolder = await drive.ensureFolder(parentId: root, name: 'Teachers Help');
            final uploadFolderId = await drive.ensureFolder(parentId: appFolder, name: 'Uploads');
            if (uploadFolderId.trim().isNotEmpty) parents = <String>[uploadFolderId.trim()];
          }
        } catch (_) {
          parents = null;
        }
      }

      final DriveUploadedFile? img = hasImage
          ? (_imageDriveFileId != null
              ? DriveUploadedFile(id: _imageDriveFileId!, name: _imageName!, mimeType: _imageMime!)
              : await drive.uploadBytes(
                  name: _imageName!,
                  mimeType: _imageMime!,
                  bytes: _imageBytes!,
                  parents: parents,
                ))
          : null;

      final DriveUploadedFile? aud = hasAudio
          ? (_audioDriveFileId != null
              ? DriveUploadedFile(id: _audioDriveFileId!, name: _audioName!, mimeType: _audioMime!)
              : await drive.uploadBytes(
                  name:
                      '${_sanitizeForDriveFilename(titleText)}-${_shortId()}${_audioExt(name: _audioName, mimeType: _audioMime)}',
                  mimeType: _audioMime!,
                  bytes: _audioBytes!,
                  parents: parents,
                ))
          : null;

    final String? annotationsJson = (_cardType == CardTypeIds.ranking || _imageAnnotations.isEmpty)
        ? ''
        : ImageAnnotations(
            version: ImageAnnotations.currentVersion,
            items: List<ImageAnnotationItem>.from(_imageAnnotations),
          ).toJsonString();

      final CardItem result;
      if (widget.existing != null) {
        result = await repo.updateCard(
          cardId: widget.existing!.id,
          title: titleText,
          cardType: _cardType,
          cardDataJson: cardDataJson,
          imageDriveFileId: img?.id ?? '',
          audioDriveFileId: aud?.id ?? '',
          imageMimeType: img?.mimeType ?? '',
          audioMimeType: aud?.mimeType ?? '',
          imageAnnotationsJson: annotationsJson,
        );
      } else {
        result = await repo.createCard(
          teacherId: widget.userId,
          tabId: widget.tabId,
          title: titleText,
          cardType: _cardType,
          cardDataJson: cardDataJson,
          imageDriveFileId: img?.id ?? '',
          audioDriveFileId: aud?.id ?? '',
          imageMimeType: img?.mimeType ?? '',
          audioMimeType: aud?.mimeType ?? '',
          imageAnnotationsJson: annotationsJson,
          sortOrder: widget.sortOrder,
        );
      }

      // Persist the card folder id (best effort).
      if (cardFolderId != null && cardFolderId.isNotEmpty) {
        try {
          if ((widget.existing?.driveFolderId ?? '').trim().isEmpty) {
            await repo.setCardDriveFolderId(cardId: result.id, driveFolderId: cardFolderId);
          }
        } catch (_) {
          // Best effort.
        }
      }

      // If the teacher picked an existing Drive file, create a shortcut in the card folder
      // (no extra storage). Only do this when we have a per-card folder.
      if (cardFolderId != null && cardFolderId.isNotEmpty) {
        try {
          final existingImgId = widget.existing?.imageDriveFileId.trim() ?? '';
          final pickedImgId = _imageDriveFileId?.trim() ?? '';
          final shouldShortcutImg = pickedImgId.isNotEmpty &&
              _imageBytes == null &&
              (widget.existing == null || pickedImgId != existingImgId);
          if (shouldShortcutImg) {
            await drive.createShortcut(
              parentId: cardFolderId,
              targetFileId: pickedImgId,
              name: '${_sanitizeForDriveFilename(titleText)}-image',
            );
          }
        } catch (_) {
          // Best effort.
        }
        try {
          final existingAudId = widget.existing?.audioDriveFileId.trim() ?? '';
          final pickedAudId = _audioDriveFileId?.trim() ?? '';
          final shouldShortcutAud = pickedAudId.isNotEmpty &&
              _audioBytes == null &&
              (widget.existing == null || pickedAudId != existingAudId);
          if (shouldShortcutAud) {
            await drive.createShortcut(
              parentId: cardFolderId,
              targetFileId: pickedAudId,
              name: '${_sanitizeForDriveFilename(titleText)}-audio',
            );
          }
        } catch (_) {
          // Best effort.
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop<CardItem>(
        (cardFolderId != null && cardFolderId.isNotEmpty && (result.driveFolderId ?? '').trim().isEmpty)
            ? CardItem(
                id: result.id,
                tabId: result.tabId,
                title: result.title,
                cardType: result.cardType,
                cardDataJson: result.cardDataJson,
                imageDriveFileId: result.imageDriveFileId,
                audioDriveFileId: result.audioDriveFileId,
                imageMimeType: result.imageMimeType,
                audioMimeType: result.audioMimeType,
                imageAnnotationsJson: result.imageAnnotationsJson,
                driveFolderId: cardFolderId,
                sortOrder: result.sortOrder,
                createdAtIso: result.createdAtIso,
              )
            : result,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opslaan mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPreview = _effectivePreviewUrl != null && !_audioDrivePreviewLoading;
    final bool isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Kaart bewerken' : 'Nieuwe kaart')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_cardType != CardTypeIds.ranking)
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Titel *',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _cardType,
            decoration: const InputDecoration(
              labelText: 'Kaart type',
              border: OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<String>>[
              for (final opt in CardTypeRegistry.teacherOptions)
                DropdownMenuItem<String>(
                  value: opt.id,
                  child: Text(opt.label),
                ),
            ],
            onChanged: _saving
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() {
                      _cardType = v;
                      if (_cardType == CardTypeIds.ranking) {
                        // Ranking kaart: alleen afbeelding.
                        _audioBytes = null;
                        _audioMime = null;
                        _audioName = null;
                        _audioDriveFileId = null;
                        _imageAnnotations.clear();
                        _arrowFrom = null;
                        _arrowTo = null;
                        _selectedAnnotIndex = null;
                        _arrowDragTarget = null;
                        _moveLastPosPx = null;
                        _lastImageRect = null;
                      }
                    });
                  },
          ),
          const SizedBox(height: 12),
          if (_cardType == CardTypeIds.imageFillIn)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Invulvraag', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fillPrompt,
                      decoration: const InputDecoration(
                        labelText: 'Zin/vraag *',
                        hintText: 'Bijv. Dit is een ...?',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fillAnswers,
                      decoration: const InputDecoration(
                        labelText: 'Goede antwoorden *',
                        hintText: 'Bijv. hond, puppy, poedel',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tip: meerdere antwoorden scheiden met komma’s.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Afbeelding', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    _imageName ?? 'Niet gekozen',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonal(
                        onPressed: _saving ? null : _pickImageFromDrive,
                        child: const Text('Uit Drive'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_imageDriveFileId != null && _imageDriveFileId!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_cardType != CardTypeIds.ranking)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: SegmentedButton<_ImageAnnotTool>(
                              segments: const <ButtonSegment<_ImageAnnotTool>>[
                                ButtonSegment<_ImageAnnotTool>(
                                  value: _ImageAnnotTool.arrow,
                                  label: Text('Pijl'),
                                  icon: Icon(Icons.arrow_right_alt),
                                ),
                                ButtonSegment<_ImageAnnotTool>(
                                  value: _ImageAnnotTool.text,
                                  label: Text('Tekst'),
                                  icon: Icon(Icons.text_fields),
                                ),
                                ButtonSegment<_ImageAnnotTool>(
                                  value: _ImageAnnotTool.move,
                                  label: Text('Verplaats'),
                                  icon: Icon(Icons.open_with_rounded),
                                ),
                              ],
                              selected: <_ImageAnnotTool>{_annotTool},
                              onSelectionChanged: (s) {
                                setState(() {
                                  _annotTool = s.first;
                                  _arrowFrom = null;
                                  _arrowTo = null;
                                  _arrowDragTarget = null;
                                  _moveLastPosPx = null;
                                });
                              },
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _imageAnnotations.isEmpty ? null : _clearAnnotations,
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: const Text('Wissen'),
                          ),
                        ],
                      ),
                    ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: ColoredBox(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: _imagePreviewLoading
                                ? const Center(
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(strokeWidth: 3),
                                    ),
                                  )
                                : (_imagePreviewError != null)
                                    ? Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Text('Afbeelding laden mislukt: $_imagePreviewError'),
                                        ),
                                      )
                                    : (_imagePreviewUrl == null)
                                        ? const Center(child: Text('Geen voorbeeld beschikbaar.'))
                                        : LayoutBuilder(
                                            builder: (context, constraints) {
                                              final size = Size(constraints.maxWidth, constraints.maxHeight);
                                              final imageRect = _imageRectForContainer(size);
                                              _lastImageRect = imageRect;
                                              final from = _arrowFrom;
                                              final to = _arrowTo;
                                              final transient = (from != null && to != null)
                                                  ? ArrowAnnotation(
                                                      fromX: from.x,
                                                      fromY: from.y,
                                                      toX: to.x,
                                                      toY: to.y,
                                                      colorHex: '#FF0000',
                                                      width: 6,
                                                    )
                                                  : null;
                                              return Stack(
                                                fit: StackFit.expand,
                                                children: <Widget>[
                                                  Image.network(
                                                    _imagePreviewUrl!,
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (context, error, stackTrace) {
                                                      return const Center(
                                                        child: Text('Afbeelding laden mislukt'),
                                                      );
                                                    },
                                                  ),
                                                  GestureDetector(
                                                    behavior: HitTestBehavior.opaque,
                                                    onTapUp: (d) => _onAnnotTap(
                                                      localPos: d.localPosition,
                                                      imageRect: imageRect,
                                                    ),
                                                    onPanStart: (d) => _onAnnotPanStart(
                                                      localPos: d.localPosition,
                                                      imageRect: imageRect,
                                                    ),
                                                    onPanUpdate: (d) => _onAnnotPanUpdate(
                                                      localPos: d.localPosition,
                                                      imageRect: imageRect,
                                                    ),
                                                    onPanEnd: (_) => _onAnnotPanEnd(),
                                                    child: CustomPaint(
                                                      painter: _ImageAnnotPainter(
                                                        items: _imageAnnotations,
                                                        transientArrow: transient,
                                                        imageRect: imageRect,
                                                        selectedIndex: _selectedAnnotIndex,
                                                        activeArrowDragTarget: _arrowDragTarget,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_cardType == CardTypeIds.soundImage)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Audio', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      _audioName ?? 'Niet gekozen',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton.tonal(
                          onPressed: _saving ? null : _pickAudioFromDrive,
                          child: const Text('Uit Drive'),
                        ),
                        FilledButton(
                          onPressed: (_saving || _recordStarting) ? null : _toggleRecord,
                          child: _recordStarting
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Starten...'),
                                  ],
                                )
                              : Text(_recording ? 'Stoppen' : 'Opnemen'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: (_saving || _recordStarting || _recording || !canPreview)
                              ? null
                              : _togglePreviewPlay,
                          icon: _audioDrivePreviewLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(_isPreviewPlaying ? Icons.pause : Icons.play_arrow),
                          label: Text(_audioDrivePreviewLoading ? 'Laden...' : 'Voorbeeld'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Opslaan...' : (isEdit ? 'Wijzigingen opslaan' : 'Kaart opslaan')),
          ),
        ],
      ),
    );
  }
}

enum _ImageAnnotTool { arrow, text, move }

enum _ArrowDragTarget { from, to, whole }

class _ImageAnnotPainter extends CustomPainter {
  const _ImageAnnotPainter({
    required this.items,
    required this.transientArrow,
    required this.imageRect,
    required this.selectedIndex,
    required this.activeArrowDragTarget,
  });

  final List<ImageAnnotationItem> items;
  final ArrowAnnotation? transientArrow;
  final Rect imageRect;
  final int? selectedIndex;
  final _ArrowDragTarget? activeArrowDragTarget;

  @override
  void paint(Canvas canvas, Size size) {
    final all = <ImageAnnotationItem>[
      ...items,
      if (transientArrow != null) transientArrow!,
    ];
    for (var i = 0; i < all.length; i++) {
      final it = all[i];
      if (it is ArrowAnnotation) {
        _paintArrow(canvas, size, it, isSelected: selectedIndex == i);
      } else if (it is TextAnnotation) {
        _paintText(canvas, size, it, isSelected: selectedIndex == i);
      }
    }
  }

  void _paintArrow(Canvas canvas, Size size, ArrowAnnotation a, {required bool isSelected}) {
    final p1 = Offset(
      imageRect.left + a.fromX * imageRect.width,
      imageRect.top + a.fromY * imageRect.height,
    );
    final p2 = Offset(
      imageRect.left + a.toX * imageRect.width,
      imageRect.top + a.toY * imageRect.height,
    );
    final dir = (p2 - p1);
    if (dir.distance < 4) return;

    final u = dir / dir.distance;
    final n = Offset(-u.dy, u.dx);
    final thickness = a.widthRel != null
        ? max(2.0, a.widthRel! * min(imageRect.width, imageRect.height))
        : max(2.0, a.width);
    final headLen = max(22.0, thickness * 4.0);
    final headWidth = max(18.0, thickness * 3.0);
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

    if (isSelected) {
      final r = max(12.0, thickness * 1.6);
      final outline = Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final bool highlightFrom = activeArrowDragTarget == _ArrowDragTarget.from;
      final bool highlightTo = activeArrowDragTarget == _ArrowDragTarget.to;

      final fromFill = Paint()
        ..color = highlightFrom ? const Color(0xFF2F6BFF) : const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill;
      final toFill = Paint()
        ..color = highlightTo ? const Color(0xFF2F6BFF) : const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(p1, r, fromFill);
      canvas.drawCircle(p1, r, outline);
      canvas.drawCircle(p2, r, toFill);
      canvas.drawCircle(p2, r, outline);
    }
  }

  void _paintText(Canvas canvas, Size size, TextAnnotation t, {required bool isSelected}) {
    final pos = Offset(
      imageRect.left + t.atX * imageRect.width,
      imageRect.top + t.atY * imageRect.height,
    );
    final style = TextStyle(
      color: _parseHex(t.colorHex, fallback: const Color(0xFF000000)),
      fontSize: t.sizeRel != null
          ? max(10.0, t.sizeRel! * min(imageRect.width, imageRect.height))
          : t.size,
      fontWeight: FontWeight.w700,
      shadows: const <Shadow>[Shadow(blurRadius: 2, offset: Offset(0, 1))],
    );
    final painter = TextPainter(
      text: TextSpan(text: t.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: imageRect.width);
    painter.paint(canvas, pos);

    if (isSelected) {
      final rect = Rect.fromLTWH(pos.dx, pos.dy, painter.width, painter.height).inflate(6);
      final paint = Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(rect, paint);
    }
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
  bool shouldRepaint(covariant _ImageAnnotPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.transientArrow != transientArrow ||
        oldDelegate.imageRect != imageRect;
  }
}

