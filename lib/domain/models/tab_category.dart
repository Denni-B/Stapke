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

  bool get isRanking => TabKind.isRanking(tabKind);

  static TabCategory fromDoc(Map<String, dynamic> doc) {
    final dynamic rawHex = doc['tabColorHex'];
    final String? hex = rawHex is String && rawHex.trim().isNotEmpty ? rawHex.trim() : null;
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
    );
  }
}

