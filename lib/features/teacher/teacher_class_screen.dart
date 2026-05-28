import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/class_public_token.dart';
import '../../domain/models/tab_category.dart';
import '../../domain/models/teachers_class.dart';
import '../../domain/tab_kind.dart';
import '../../services/appwrite/auth_controller.dart';
import '../../services/appwrite/teacher_repository.dart';
import '../../services/drive/drive_api.dart';
import '../../utils/tab_color.dart';
import '../../widgets/tab_color_picker_dialog.dart';
import 'teacher_navigation.dart';
import 'teacher_tab_screen.dart';

class TeacherClassScreen extends ConsumerStatefulWidget {
  const TeacherClassScreen({super.key, required this.userId, required this.clazz});

  final String userId;
  final TeachersClass clazz;

  @override
  ConsumerState<TeacherClassScreen> createState() => _TeacherClassScreenState();
}

class _TeacherClassScreenState extends ConsumerState<TeacherClassScreen> {
  late final TextEditingController _tokenController;
  late Future<List<TabCategory>> _tabsFuture;
  bool _tokenSaving = false;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.clazz.publicToken);
    _tabsFuture = ref.read(teacherRepositoryProvider).listTabs(classId: widget.clazz.id);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TeacherClassScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clazz.id != widget.clazz.id) {
      _tabsFuture = ref.read(teacherRepositoryProvider).listTabs(classId: widget.clazz.id);
    }
    if (oldWidget.clazz.id == widget.clazz.id &&
        oldWidget.clazz.publicToken != widget.clazz.publicToken) {
      _tokenController.text = widget.clazz.publicToken;
    }
  }

  String _studentUrlForToken(String token) {
    final path = '/class/$token';
    if (kIsWeb) {
      return Uri.parse(Uri.base.origin).resolveUri(Uri(path: path)).toString();
    }
    return path;
  }

  String _previewToken() {
    final normalized = normalizeClassPublicTokenInput(_tokenController.text.trim());
    if (normalized.isNotEmpty) return normalized;
    return widget.clazz.publicToken;
  }

  void _refreshTabs() {
    setState(() {
      _tabsFuture = ref.read(teacherRepositoryProvider).listTabs(classId: widget.clazz.id);
    });
  }

  Future<String?> _promptText(
    BuildContext context, {
    required String dialogTitle,
    required String fieldLabel,
    String? initial,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: fieldLabel,
              border: const OutlineInputBorder(),
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

  void _applySuggestedToken() {
    final authUser = ref.read(authControllerProvider).value;
    final teacherName = (authUser?.name ?? 'Leraar').trim();
    final suggestion = buildClassPublicToken(
      teacherName: teacherName.isEmpty ? 'leraar' : teacherName,
      className: widget.clazz.name,
    );
    if (suggestion.isEmpty) return;
    setState(() => _tokenController.text = suggestion);
  }

  Future<void> _saveToken() async {
    final normalized = normalizeClassPublicTokenInput(_tokenController.text.trim());
    if (normalized.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voer een niet-leeg token in (letters, cijfers, liggende streepjes).')),
      );
      return;
    }
    if (normalized == widget.clazz.publicToken) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token niet gewijzigd.')),
      );
      return;
    }

    setState(() => _tokenSaving = true);
    try {
      final repo = ref.read(teacherRepositoryProvider);
      final updated = await repo.updateClassPublicToken(
        classId: widget.clazz.id,
        requestedToken: normalized,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leerlinglink bijgewerkt. Deel de nieuwe URL met leerlingen.')),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TeacherClassScreen(userId: widget.userId, clazz: updated),
        ),
      );
    } on ArgumentError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Token bijwerken mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _tokenSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(teacherRepositoryProvider);
    final previewUrl = _studentUrlForToken(_previewToken());

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clazz.name),
        actions: <Widget>[
          Tooltip(
            message: 'Startpagina Lerarenhulp — leerlingtoegang, leraar inloggen',
            child: TextButton.icon(
              onPressed: () => goToTeachersHelpStart(context),
              icon: const Icon(Icons.home_rounded),
              label: const Text('Startpagina'),
            ),
          ),
          Tooltip(
            message:
                'Terug naar je klassen — open daar de leerlinglink om de klas te proberen',
            child: FilledButton.tonalIcon(
              onPressed: () => popToTeacherClassList(context),
              icon: const Icon(Icons.grid_view_rounded),
              label: const Text('Klassen'),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'rename_class') {
                final name = await _promptText(
                  context,
                  dialogTitle: 'Klas hernoemen',
                  fieldLabel: 'Klasnaam',
                  initial: widget.clazz.name,
                  confirmLabel: 'Opslaan',
                );
                if (name == null) return;
                try {
                  final updated = await repo.updateClassName(
                    classId: widget.clazz.id,
                    name: name,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => TeacherClassScreen(userId: widget.userId, clazz: updated),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Klas hernoemen mislukt: $e')),
                  );
                }
              } else if (value == 'delete_class') {
                final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Klas verwijderen?'),
                        content: Text(
                          'Verwijdert "${widget.clazz.name}", alle tabbladen en alle kaarten. '
                          'Drive-bestanden blijven staan.',
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
                  await repo.deleteClassCascade(classId: widget.clazz.id);
                  if (!context.mounted) return;
                  context.go('/teacher');
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Klas verwijderen mislukt: $e')),
                  );
                }
              }
            },
            itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'rename_class',
                child: Text('Klas hernoemen'),
              ),
              PopupMenuItem<String>(
                value: 'delete_class',
                child: Text(
                  'Klas verwijderen',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<TabCategory>>(
        future: _tabsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fout: ${snapshot.error}'));
          }
          final tabs = snapshot.data ?? <TabCategory>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Leerlinglink',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Leerlingen openen deze klas met het token in de site-URL (max. 64 tekens, uniek). '
                        'Als je het wijzigt, werken oude bladwijzers niet meer.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tokenController,
                        enabled: !_tokenSaving,
                        decoration: const InputDecoration(
                          labelText: 'Linktoken',
                          border: OutlineInputBorder(),
                          hintText: 'leraarnaam_klasnaam',
                        ),
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_-]')),
                        ],
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          FilledButton.tonal(
                            onPressed: _tokenSaving ? null : _applySuggestedToken,
                            child: const Text('Gebruik leraar- en klasnaam'),
                          ),
                          FilledButton(
                            onPressed: _tokenSaving ? null : _saveToken,
                            child: _tokenSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Token opslaan'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Voorbeeld-URL',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(previewUrl),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Tabbladen en rankings',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () async {
                      final title = await _promptText(
                        context,
                        dialogTitle: 'Nieuw tabblad',
                        fieldLabel: 'Titel tabblad',
                        initial: null,
                        confirmLabel: 'Aanmaken',
                      );
                      if (title == null) return;
                      if (!context.mounted) return;
                      final String? pickedHex =
                          await showTabColorPickerDialog(context, currentHex: null);
                      if (!context.mounted) return;
                      final sortOrder = tabs.length;
                      try {
                        final created = await repo.createTab(
                          teacherId: widget.userId,
                          classId: widget.clazz.id,
                          title: title,
                          sortOrder: sortOrder,
                          tabColorHex:
                              pickedHex == null || pickedHex.isEmpty ? null : pickedHex,
                        );
                        try {
                          final drive = ref.read(driveApiProvider);
                          final root = await drive.getRootFolderId();
                          if (root.trim().isNotEmpty) {
                            final appFolder = await drive.ensureFolder(parentId: root, name: 'Teachers Help');
                            final classesFolder = await drive.ensureFolder(parentId: appFolder, name: 'Klassen');
                            final classFolder = widget.clazz.driveFolderId?.trim().isNotEmpty == true
                                ? widget.clazz.driveFolderId!.trim()
                                : await drive.ensureFolder(parentId: classesFolder, name: widget.clazz.name);
                            if (widget.clazz.driveFolderId == null || widget.clazz.driveFolderId!.trim().isEmpty) {
                              await repo.setClassDriveFolderId(classId: widget.clazz.id, driveFolderId: classFolder);
                            }
                            final tabsFolder = await drive.ensureFolder(parentId: classFolder, name: 'Tabbladen');
                            final tabFolder = await drive.ensureFolder(parentId: tabsFolder, name: created.title);
                            await repo.setTabDriveFolderId(tabId: created.id, driveFolderId: tabFolder);
                          }
                        } catch (_) {
                          // Best effort.
                        }
                        if (!context.mounted) return;
                        // Optimistically update UI to avoid eventual-consistency delays.
                        setState(() {
                          final next = <TabCategory>[...tabs, created]
                            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                          _tabsFuture = Future.value(next);
                        });

                        // Also refresh from backend in the background.
                        // ignore: unawaited_futures
                        Future<void>.delayed(const Duration(milliseconds: 400), () async {
                          if (!mounted) return;
                          _refreshTabs();
                        });
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Tabblad aanmaken mislukt: $e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Nieuw tabblad'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final title = await _promptText(
                        context,
                        dialogTitle: 'Nieuwe ranking',
                        fieldLabel: 'Titel ranking',
                        initial: null,
                        confirmLabel: 'Aanmaken',
                      );
                      if (title == null) return;
                      if (!context.mounted) return;
                      final String? pickedHex =
                          await showTabColorPickerDialog(context, currentHex: null);
                      if (!context.mounted) return;
                      final sortOrder = tabs.length;
                      try {
                        final created = await repo.createTab(
                          teacherId: widget.userId,
                          classId: widget.clazz.id,
                          title: title,
                          sortOrder: sortOrder,
                          tabColorHex:
                              pickedHex == null || pickedHex.isEmpty ? null : pickedHex,
                          tabKind: TabKind.ranking,
                        );
                        try {
                          final drive = ref.read(driveApiProvider);
                          final root = await drive.getRootFolderId();
                          if (root.trim().isNotEmpty) {
                            final appFolder =
                                await drive.ensureFolder(parentId: root, name: 'Teachers Help');
                            final classesFolder =
                                await drive.ensureFolder(parentId: appFolder, name: 'Klassen');
                            final classFolder = widget.clazz.driveFolderId?.trim().isNotEmpty == true
                                ? widget.clazz.driveFolderId!.trim()
                                : await drive.ensureFolder(
                                    parentId: classesFolder,
                                    name: widget.clazz.name,
                                  );
                            if (widget.clazz.driveFolderId == null ||
                                widget.clazz.driveFolderId!.trim().isEmpty) {
                              await repo.setClassDriveFolderId(
                                classId: widget.clazz.id,
                                driveFolderId: classFolder,
                              );
                            }
                            final rankingsFolder =
                                await drive.ensureFolder(parentId: classFolder, name: 'Rankings');
                            final rankingFolder =
                                await drive.ensureFolder(parentId: rankingsFolder, name: created.title);
                            await repo.setTabDriveFolderId(
                              tabId: created.id,
                              driveFolderId: rankingFolder,
                            );
                          }
                        } catch (_) {
                          // Best effort.
                        }
                        if (!context.mounted) return;
                        setState(() {
                          final next = <TabCategory>[...tabs, created]
                            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                          _tabsFuture = Future.value(next);
                        });
                        // ignore: unawaited_futures
                        Future<void>.delayed(const Duration(milliseconds: 400), () async {
                          if (!mounted) return;
                          _refreshTabs();
                        });
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ranking aanmaken mislukt: $e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.leaderboard),
                    label: const Text('Nieuwe ranking'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final title = await _promptText(
                        context,
                        dialogTitle: 'Nieuwe stemming',
                        fieldLabel: 'Titel stemming',
                        initial: null,
                        confirmLabel: 'Aanmaken',
                      );
                      if (title == null) return;
                      if (!context.mounted) return;
                      final String? pickedHex =
                          await showTabColorPickerDialog(context, currentHex: null);
                      if (!context.mounted) return;
                      final sortOrder = tabs.length;
                      try {
                        final created = await repo.createTab(
                          teacherId: widget.userId,
                          classId: widget.clazz.id,
                          title: title,
                          sortOrder: sortOrder,
                          tabColorHex: pickedHex == null || pickedHex.isEmpty ? null : pickedHex,
                          tabKind: TabKind.nameVoting,
                        );
                        // Default weights: 3-2-1
                        try {
                          await repo.updateNameVotingWeights(
                            tabId: created.id,
                            weights: const <int>[3, 2, 1],
                          );
                        } catch (_) {
                          // Best effort.
                        }
                        // Best effort Drive folder structure (align with other types).
                        try {
                          final drive = ref.read(driveApiProvider);
                          final root = await drive.getRootFolderId();
                          if (root.trim().isNotEmpty) {
                            final appFolder =
                                await drive.ensureFolder(parentId: root, name: 'Teachers Help');
                            final classesFolder =
                                await drive.ensureFolder(parentId: appFolder, name: 'Klassen');
                            final classFolder = widget.clazz.driveFolderId?.trim().isNotEmpty == true
                                ? widget.clazz.driveFolderId!.trim()
                                : await drive.ensureFolder(
                                    parentId: classesFolder,
                                    name: widget.clazz.name,
                                  );
                            if (widget.clazz.driveFolderId == null ||
                                widget.clazz.driveFolderId!.trim().isEmpty) {
                              await repo.setClassDriveFolderId(
                                classId: widget.clazz.id,
                                driveFolderId: classFolder,
                              );
                            }
                            final votingsFolder = await drive.ensureFolder(
                              parentId: classFolder,
                              name: 'Stemmingen',
                            );
                            final votingFolder = await drive.ensureFolder(
                              parentId: votingsFolder,
                              name: created.title,
                            );
                            await repo.setTabDriveFolderId(
                              tabId: created.id,
                              driveFolderId: votingFolder,
                            );
                          }
                        } catch (_) {
                          // Best effort.
                        }
                        if (!context.mounted) return;
                        setState(() {
                          final next = <TabCategory>[...tabs, created]
                            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                          _tabsFuture = Future.value(next);
                        });
                        // ignore: unawaited_futures
                        Future<void>.delayed(const Duration(milliseconds: 400), () async {
                          if (!mounted) return;
                          _refreshTabs();
                        });
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Stemming aanmaken mislukt: $e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.how_to_vote_outlined),
                    label: const Text('Nieuwe stemming'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (tabs.isEmpty)
                const Text('Nog geen tabbladen of rankings.'),
              ...tabs.map(
                (t) => ListTile(
                  leading: _ClassTabLeading(
                    tabColorHex: t.tabColorHex,
                    isRanking: t.isRanking,
                    isNameVoting: t.isNameVoting,
                  ),
                  title: Text(t.title),
                  subtitle: Text(t.isRanking ? 'Ranking' : (t.isNameVoting ? 'Stemming' : 'Tabblad')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) async {
                          if (value == 'color') {
                            final String? picked = await showTabColorPickerDialog(
                              context,
                              currentHex: t.tabColorHex,
                            );
                            if (picked == null || !context.mounted) return;
                            try {
                              await repo.updateTabColor(
                                tabId: t.id,
                                tabColorHex: picked.isEmpty ? null : picked,
                              );
                              if (!context.mounted) return;
                              _refreshTabs();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Tabbladkleur bijwerken mislukt: $e')),
                              );
                            }
                          } else if (value == 'edit') {
                            final title = await _promptText(
                              context,
                              dialogTitle: 'Tabblad hernoemen',
                              fieldLabel: 'Titel tabblad',
                              initial: t.title,
                              confirmLabel: 'Opslaan',
                            );
                            if (title == null) return;
                            try {
                              final updated = await repo.updateTabTitle(tabId: t.id, title: title);
                              final folderId = updated.driveFolderId?.trim();
                              if (folderId != null && folderId.isNotEmpty) {
                                final drive = ref.read(driveApiProvider);
                                await drive.renameFolder(folderId: folderId, newName: updated.title);
                              }
                              if (!context.mounted) return;
                              _refreshTabs();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Tabblad hernoemen mislukt: $e')),
                              );
                            }
                          } else if (value == 'delete') {
                            final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Tabblad verwijderen?'),
                                    content: Text(
                                      t.isRanking
                                          ? 'Verwijdert ranking „${t.title}”, alle foto\'s en alle stemmen. '
                                              'Drive-bestanden blijven staan.'
                                          : 'Verwijdert tabblad „${t.title}” en alle bijbehorende kaarten. '
                                              'Drive-bestanden blijven staan.',
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(false),
                                        child: const Text('Annuleren'),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              Theme.of(ctx).colorScheme.error,
                                          foregroundColor:
                                              Theme.of(ctx).colorScheme.onError,
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
                              final folderId = t.driveFolderId?.trim();
                              if (folderId != null && folderId.isNotEmpty) {
                                final drive = ref.read(driveApiProvider);
                                await drive.trashAndLog(
                                  fileId: folderId,
                                  name: t.title,
                                  kind: 'tab-folder',
                                );
                              }
                              await repo.deleteTabCascade(tabId: t.id);
                              if (!context.mounted) return;
                              _refreshTabs();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Tabblad verwijderen mislukt: $e')),
                              );
                            }
                          }
                        },
                        itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'color',
                            child: Text('Tabbladkleur'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'edit',
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
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TeacherTabScreen(userId: widget.userId, tab: t),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

}

class _ClassTabLeading extends StatelessWidget {
  const _ClassTabLeading({
    required this.tabColorHex,
    this.isRanking = false,
    this.isNameVoting = false,
  });

  final String? tabColorHex;
  final bool isRanking;
  final bool isNameVoting;

  @override
  Widget build(BuildContext context) {
    final icon = isRanking
        ? Icons.leaderboard
        : (isNameVoting ? Icons.how_to_vote_outlined : Icons.folder_outlined);
    final Color? c = parseTabColorHex(tabColorHex);
    if (c == null) {
      return CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        radius: 18,
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: c,
      radius: 18,
      child: Icon(
        icon,
        color: foregroundOnTabColor(c),
      ),
    );
  }
}

