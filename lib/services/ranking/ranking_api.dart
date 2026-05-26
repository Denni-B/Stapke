import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../appwrite/appwrite_providers.dart';

final rankingApiProvider = Provider<RankingApi>((ref) {
  final functions = ref.watch(appwriteFunctionsProvider);
  final config = ref.watch(appConfigProvider);
  return RankingApi(functions: functions, functionId: config.rankingFunctionId);
});

class StudentVote {
  const StudentVote({
    required this.rankingItemId,
    required this.score,
    required this.comment,
    this.updatedAt,
  });

  final String rankingItemId;
  final int score;
  final String comment;
  final String? updatedAt;
}

class RankingApi {
  RankingApi({required this.functions, required this.functionId});

  final Functions functions;
  final String functionId;

  Map<String, dynamic> _decodeJsonObject(String responseBody, {required String context}) {
    final body = responseBody.trim();
    if (body.isEmpty) {
      throw StateError('$context: lege antwoordtekst.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw StateError('$context: verwachte een JSON-object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> submitVote({
    required String publicToken,
    required String rankingItemId,
    required String studentName,
    required int score,
    String? comment,
  }) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/public/submit',
      body: jsonEncode(<String, dynamic>{
        'publicToken': publicToken,
        'rankingItemId': rankingItemId,
        'studentName': studentName,
        'score': score,
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Ranking submit');
    if (data['ok'] != true) {
      final msg = data['message'] as String? ?? 'Stem opslaan mislukt.';
      throw StateError(msg);
    }
  }

  Future<List<StudentVote>> fetchMyVotes({
    required String publicToken,
    required String tabId,
    required String studentName,
  }) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/public/my-votes',
      body: jsonEncode(<String, dynamic>{
        'publicToken': publicToken,
        'tabId': tabId,
        'studentName': studentName,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Ranking my-votes');
    final votesAny = data['votes'];
    if (votesAny is! List) return const <StudentVote>[];
    return votesAny.map((v) {
      final m = Map<String, dynamic>.from(v as Map);
      return StudentVote(
        rankingItemId: m['rankingItemId'] as String,
        score: (m['score'] as num).toInt(),
        comment: (m['comment'] as String?) ?? '',
        updatedAt: m['updatedAt'] as String?,
      );
    }).toList();
  }
}
