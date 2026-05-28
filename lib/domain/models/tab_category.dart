import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../tab_kind.dart';

@immutable
class TabCategory {
  const TabCategory({
    required this.id,
    required this.classId,
    required this.title,
    required this.sortOrder,
    required this.driveFolderId,
    required this.tabKind,
    this.tabColorHex,
    this.nameVotingWeightsJson,
  });

  final String id;
  final String classId;
  final String title;
  final int sortOrder;
  final String? driveFolderId;

  /// `cards` (default) or `ranking`.
  final String tabKind;

  /// Optional `#RRGGBB` accent for student UI and tab list.
  final String? tabColorHex;

  /// JSON string with weights per rank, e.g. `[5,2]`. Only used for `name_voting` tabs.
  final String? nameVotingWeightsJson;

  bool get isRanking => TabKind.isRanking(tabKind);
  bool get isNameVoting => TabKind.isNameVoting(tabKind);

  List<int> get nameVotingWeights {
    final raw = (nameVotingWeightsJson ?? '').trim();
    if (raw.isEmpty) return const <int>[3, 2, 1];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <int>[3, 2, 1];
      final weights = decoded
          .map((e) => (e is num) ? e.toInt() : int.tryParse('$e'))
          .whereType<int>()
          .where((w) => w > 0)
          .toList();
      if (weights.isEmpty) return const <int>[3, 2, 1];
      return weights;
    } catch (_) {
      return const <int>[3, 2, 1];
    }
  }

  static TabCategory fromDoc(Map<String, dynamic> doc) {
    final dynamic rawHex = doc['tabColorHex'];
    final String? hex = rawHex is String && rawHex.trim().isNotEmpty ? rawHex.trim() : null;
    final dynamic rawWeights = doc['nameVotingWeightsJson'];
    final String? weightsJson =
        rawWeights is String && rawWeights.trim().isNotEmpty ? rawWeights.trim() : null;
    return TabCategory(
      id: doc['\$id'] as String,
      classId: doc['classId'] as String,
      title: doc['title'] as String,
      sortOrder: (doc['sortOrder'] as num).toInt(),
      driveFolderId: (doc['driveFolderId'] as String?)?.trim().isEmpty == true
          ? null
          : (doc['driveFolderId'] as String?),
      tabKind: TabKind.normalize(doc['tabKind'] as String?),
      tabColorHex: hex,
      nameVotingWeightsJson: weightsJson,
    );
  }
}

