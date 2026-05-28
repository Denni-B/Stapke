import 'package:flutter/foundation.dart';

@immutable
class ClassStudent {
  const ClassStudent({
    required this.id,
    required this.classId,
    required this.studentId,
    required this.name,
    required this.updatedAtIso,
  });

  final String id;
  final String classId;
  final String studentId;
  final String name;
  final String updatedAtIso;

  static ClassStudent fromDoc(Map<String, dynamic> doc) {
    return ClassStudent(
      id: doc['\$id'] as String,
      classId: doc['classId'] as String,
      studentId: doc['studentId'] as String,
      name: doc['name'] as String,
      updatedAtIso: (doc['updatedAt'] as String?) ?? '',
    );
  }
}

