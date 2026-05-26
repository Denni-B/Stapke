import 'package:flutter/foundation.dart';

@immutable
class RankingItem {
  const RankingItem({
    required this.id,
    required this.tabId,
    required this.title,
    required this.imageDriveFileId,
    required this.imageMimeType,
    required this.sortOrder,
  });

  final String id;
  final String tabId;
  final String? title;
  final String imageDriveFileId;
  final String imageMimeType;
  final int sortOrder;

  String get displayLabel {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return 'Foto ${sortOrder + 1}';
  }

  static RankingItem fromDoc(Map<String, dynamic> doc) {
    return RankingItem(
      id: doc['\$id'] as String,
      tabId: doc['tabId'] as String,
      title: (doc['title'] as String?)?.trim().isEmpty == true
          ? null
          : (doc['title'] as String?),
      imageDriveFileId: doc['imageDriveFileId'] as String,
      imageMimeType: (doc['imageMimeType'] as String?) ?? 'image/jpeg',
      sortOrder: (doc['sortOrder'] as num).toInt(),
    );
  }
}
