import 'package:flutter/foundation.dart';

@immutable
class RankingSubmission {
  const RankingSubmission({
    required this.id,
    required this.classId,
    required this.tabId,
    required this.rankingItemId,
    required this.studentName,
    required this.score,
    required this.comment,
    required this.createdAtIso,
    required this.updatedAtIso,
  });

  final String id;
  final String classId;
  final String tabId;
  final String rankingItemId;
  final String studentName;
  final int score;
  final String? comment;
  final String createdAtIso;
  final String updatedAtIso;

  static RankingSubmission fromDoc(Map<String, dynamic> doc) {
    final String? rawComment = doc['comment'] as String?;
    return RankingSubmission(
      id: doc['\$id'] as String,
      classId: doc['classId'] as String,
      tabId: doc['tabId'] as String,
      rankingItemId: doc['rankingItemId'] as String,
      studentName: doc['studentName'] as String,
      score: (doc['score'] as num).toInt(),
      comment: rawComment == null || rawComment.trim().isEmpty ? null : rawComment.trim(),
      createdAtIso: doc['createdAt'] as String,
      updatedAtIso: doc['updatedAt'] as String,
    );
  }
}
