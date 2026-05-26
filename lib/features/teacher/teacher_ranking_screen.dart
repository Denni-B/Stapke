import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ranking_item.dart';
import '../../domain/models/tab_category.dart';
import '../../services/appwrite/appwrite_providers.dart';
import '../../services/appwrite/teacher_repository.dart';
import '../../services/drive/drive_api.dart';
import '../../services/drive/drive_picker.dart';
import '../../utils/tab_color.dart';
import 'teacher_ranking_results_screen.dart';

class TeacherRankingScreen extends ConsumerStatefulWidget {
  const TeacherRankingScreen({super.key, required this.userId, required this.tab});

  final String userId;
  final TabCategory tab;

  @override
  ConsumerState<TeacherRankingScreen> createState() => _TeacherRankingScreenState();
}

class _TeacherRankingScreenState extends ConsumerState<TeacherRankingScreen> {
  late Future<List<RankingItem>> _itemsFuture;
  final DrivePickerService _drivePicker = DrivePickerService.create();
  final Map<String, String> _previewCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _itemsFuture = ref.read(teacherRepositoryProvider).listRankingItems(tabId: widget.tab.id);
  }

  Future<void> _pickAndAdd() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drive-kiezer werkt alleen in de webversie.')),
      );
      return;
    }
    final config = ref.read(appConfigProvider);
    if (config.googleApiKey.trim().isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Google API-sleutel ontbreekt'),
          content: const Text(
            'De Drive-kiezer heeft een Google API key nodig.\n\n'
            'Lokaal starten met bijvoorbeeld:\n'
            'flutter run -d edge --no-web-resources-cdn '
            '--dart-define=GOOGLE_API_KEY="jouw-sleutel"\n\n'
            'Of: .\\scripts\\run_web.ps1 --dart-define=GOOGLE_API_KEY="jouw-sleutel"\n\n'
            'Maak de key in Google Cloud (APIs & Services → Credentials), '
            'beperk HTTP-verwijzers tot localhost en je site-URL.',
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    try {
      final drive = ref.read(driveApiProvider);
      final token = await drive.getAccessToken();
      final picked = await _drivePicker.pick(
        googleApiKey: config.googleApiKey,
        oauthAccessToken: token,
        isImage: true,
      );
      if (picked == null) return;

      final repo = ref.read(teacherRepositoryProvider);
      final current = await repo.listRankingItems(tabId: widget.tab.id);
      await repo.createRankingItem(
        teacherId: widget.userId,
        tabId: widget.tab.id,
        imageDriveFileId: picked.id,
        imageMimeType: picked.mimeType,
        title: picked.name,
        sortOrder: current.length,
      );
      if (!mounted) return;
      setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Foto toevoegen mislukt: $e')),
      );
    }
  }

  Future<String?> _imagePreview(String fileId) async {
    if (fileId.trim().isEmpty) return null;
    if (_previewCache.containsKey(fileId)) return _previewCache[fileId];
    try {
      final url = await ref.read(driveApiProvider).downloadDataUrl(fileId: fileId);
      _previewCache[fileId] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteItem(RankingItem item) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Foto verwijderen?'),
            content: Text('Verwijdert „${item.displayLabel}” en alle stemmen op deze foto.'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuleren')),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Verwijderen'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await ref.read(teacherRepositoryProvider).deleteRankingItem(itemId: item.id);
      if (!mounted) return;
      setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verwijderen mislukt: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color? accent = parseTabColorHex(widget.tab.tabColorHex);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tab.title),
        backgroundColor: accent,
        foregroundColor: accent != null ? foregroundOnTabColor(accent) : null,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Resultaten',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TeacherRankingResultsScreen(
                    userId: widget.userId,
                    tab: widget.tab,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: kIsWeb
          ? FloatingActionButton.extended(
              onPressed: _pickAndAdd,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Foto uit Drive'),
            )
          : null,
      body: FutureBuilder<List<RankingItem>>(
        future: _itemsFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Fout: ${snap.error}'));
          }
          final items = snap.data ?? const <RankingItem>[];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nog geen foto\'s. Voeg afbeeldingen toe uit Google Drive zodat leerlingen kunnen stemmen.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex -= 1;
              final reordered = List<RankingItem>.from(items);
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              final repo = ref.read(teacherRepositoryProvider);
              for (var i = 0; i < reordered.length; i++) {
                if (reordered[i].sortOrder != i) {
                  await repo.updateRankingItem(itemId: reordered[i].id, sortOrder: i);
                }
              }
              if (!mounted) return;
              setState(_reload);
            },
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                key: ValueKey<String>(item.id),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: SizedBox(
                    width: 56,
                    height: 56,
                    child: FutureBuilder<String?>(
                      future: _imagePreview(item.imageDriveFileId),
                      builder: (context, imgSnap) {
                        final url = imgSnap.data;
                        if (url == null) {
                          return const Center(child: Icon(Icons.image_outlined));
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(url, fit: BoxFit.cover),
                        );
                      },
                    ),
                  ),
                  title: Text(item.displayLabel),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteItem(item),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
