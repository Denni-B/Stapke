import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../appwrite/appwrite_providers.dart';

final classroomApiProvider = Provider<ClassroomApi>((ref) {
  final functions = ref.watch(appwriteFunctionsProvider);
  final config = ref.watch(appConfigProvider);
  return ClassroomApi(functions: functions, functionId: config.classroomFunctionId);
});

class ClassroomStudent {
  const ClassroomStudent({
    required this.studentId,
    required this.name,
    this.updatedAt,
  });

  final String studentId;
  final String name;
  final String? updatedAt;
}

class NameVoteBallot {
  const NameVoteBallot({
    required this.choiceStudentIds,
    this.updatedAt,
  });

  final List<String> choiceStudentIds;
  final String? updatedAt;
}

class NameVoteResultItem {
  const NameVoteResultItem({
    required this.studentId,
    required this.name,
    required this.pointsTotal,
  });

  final String studentId;
  final String name;
  final int pointsTotal;
}

class ClassroomApi {
  ClassroomApi({required this.functions, required this.functionId});

  final Functions functions;
  final String functionId;

  Map<String, dynamic> _decodeJsonObject(
    String responseBody, {
    required String context,
    int? statusCode,
  }) {
    final body = responseBody.trim();
    if (body.isEmpty) {
      throw StateError(
        '$context: lege antwoordtekst'
        '${statusCode != null ? ' (status $statusCode)' : ''}. '
        'Check in Appwrite Console → Functions → $functionId → Executions/Logs voor details.',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw StateError('$context: verwachte een JSON-object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> registerStudent({
    required String publicToken,
    required String classId,
    required String studentId,
    required String name,
  }) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/public/register-student',
      body: jsonEncode(<String, dynamic>{
        'publicToken': publicToken,
        'classId': classId,
        'studentId': studentId,
        'name': name,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(
      result.responseBody,
      context: 'Classroom register-student',
      statusCode: result.responseStatusCode,
    );
    if (data['ok'] != true) {
      final msg = data['message'] as String? ?? 'Registratie mislukt.';
      throw StateError(msg);
    }
  }

  Future<List<ClassroomStudent>> listStudents({
    required String publicToken,
    required String classId,
  }) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/public/list-students',
      body: jsonEncode(<String, dynamic>{
        'publicToken': publicToken,
        'classId': classId,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(
      result.responseBody,
      context: 'Classroom list-students',
      statusCode: result.responseStatusCode,
    );
    final listAny = data['students'];
    if (listAny is! List) return const <ClassroomStudent>[];
    return listAny.map((v) {
      final m = Map<String, dynamic>.from(v as Map);
      return ClassroomStudent(
        studentId: m['studentId'] as String,
        name: (m['name'] as String?) ?? '',
        updatedAt: m['updatedAt'] as String?,
      );
    }).toList();
  }

  Future<void> submitNameVote({
    required String publicToken,
    required String tabId,
    required String voterStudentId,
    required List<String> choiceStudentIds,
  }) async {
    if (choiceStudentIds.isEmpty) {
      throw ArgumentError('Kies minstens één naam.');
    }
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/public/submit-name-vote',
      body: jsonEncode(<String, dynamic>{
        'publicToken': publicToken,
        'tabId': tabId,
        'voterStudentId': voterStudentId,
        'choiceStudentIds': choiceStudentIds,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(
      result.responseBody,
      context: 'Classroom submit-name-vote',
      statusCode: result.responseStatusCode,
    );
    if (data['ok'] != true) {
      final msg = data['message'] as String? ?? 'Stem opslaan mislukt.';
      throw StateError(msg);
    }
  }

  Future<NameVoteBallot?> fetchMyNameVote({
    required String publicToken,
    required String tabId,
    required String voterStudentId,
  }) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/public/my-name-vote',
      body: jsonEncode(<String, dynamic>{
        'publicToken': publicToken,
        'tabId': tabId,
        'voterStudentId': voterStudentId,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(
      result.responseBody,
      context: 'Classroom my-name-vote',
      statusCode: result.responseStatusCode,
    );
    final voteAny = data['vote'];
    if (voteAny is! Map) return null;
    final vote = Map<String, dynamic>.from(voteAny);
    final choicesAny = vote['choiceStudentIds'];
    final choices = (choicesAny is List)
        ? choicesAny.map((e) => (e as String?) ?? '').where((s) => s.trim().isNotEmpty).toList()
        : const <String>[];
    return NameVoteBallot(
      choiceStudentIds: choices,
      updatedAt: vote['updatedAt'] as String?,
    );
  }

  Future<List<NameVoteResultItem>> teacherNameVoteResults({required String tabId}) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/teacher/name-vote-results',
      body: jsonEncode(<String, dynamic>{'tabId': tabId}),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(
      result.responseBody,
      context: 'Classroom teacher name-vote-results',
      statusCode: result.responseStatusCode,
    );
    final itemsAny = data['results'];
    if (itemsAny is! List) return const <NameVoteResultItem>[];
    return itemsAny.map((v) {
      final m = Map<String, dynamic>.from(v as Map);
      return NameVoteResultItem(
        studentId: m['studentId'] as String,
        name: (m['name'] as String?) ?? '',
        pointsTotal: (m['pointsTotal'] as num).toInt(),
      );
    }).toList();
  }
}

