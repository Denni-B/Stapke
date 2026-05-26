import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ranking_viewer_screen.dart';
import 'viewer/card_viewer_screen.dart';
import '../../services/appwrite/student_repository.dart';
import '../../domain/models/tab_category.dart';
import '../../utils/tab_color.dart';

class TabPickerScreen extends ConsumerWidget {
  const TabPickerScreen({
    super.key,
    required this.publicToken,
    required this.classId,
    required this.studentName,
    required this.className,
    required this.onChangeName,
  });

  final String publicToken;
  final String classId;
  final String studentName;
  final String className;
  final VoidCallback onChangeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(studentRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kies een activiteit'),
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.person_outline),
            tooltip: studentName,
            onSelected: (value) {
              if (value == 'change_name') onChangeName();
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                enabled: false,
                child: Text('Ingelogd als $studentName'),
              ),
              const PopupMenuItem<String>(
                value: 'change_name',
                child: Text('Naam wijzigen'),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder(
        future: repo.listTabs(classId),
        builder: (context, tabsSnap) {
          if (tabsSnap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (tabsSnap.hasError) {
            return Center(child: Text('Fout: ${tabsSnap.error}'));
          }
          final tabs = tabsSnap.data ?? const <TabCategory>[];
          if (tabs.isEmpty) {
            return const Center(child: Text('Nog geen tabbladen of rankings.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tabs.length,
            separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int index) {
              final TabCategory tab = tabs[index];
              final Color? accent = parseTabColorHex(tab.tabColorHex);
              final theme = Theme.of(context);
              final Color tileBg = accent ?? theme.colorScheme.surfaceContainerHighest;
              final Color titleColor =
                  accent != null ? foregroundOnTabColor(accent) : theme.colorScheme.onSurface;
              final Color subtitleColor = accent != null
                  ? foregroundOnTabColor(accent).withValues(alpha: 0.85)
                  : theme.colorScheme.onSurfaceVariant;
              final Color iconColor =
                  accent != null ? foregroundOnTabColor(accent) : theme.colorScheme.onSurfaceVariant;
              final bool isRanking = tab.isRanking;
              return ListTile(
                leading: Icon(
                  isRanking ? Icons.leaderboard : Icons.folder_outlined,
                  color: iconColor,
                ),
                tileColor: tileBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(
                  tab.title,
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text(
                  isRanking ? 'Ranking · $className' : 'Tabblad · $className',
                  style: TextStyle(color: subtitleColor),
                ),
                trailing: Icon(Icons.chevron_right, color: iconColor),
                onTap: () {
                  if (isRanking) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RankingViewerScreen(
                          publicToken: publicToken,
                          tabId: tab.id,
                          tabTitle: tab.title,
                          tabColorHex: tab.tabColorHex,
                          studentName: studentName,
                        ),
                      ),
                    );
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CardViewerScreen(
                          publicToken: publicToken,
                          tabId: tab.id,
                          tabTitle: tab.title,
                          tabColorHex: tab.tabColorHex,
                        ),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
