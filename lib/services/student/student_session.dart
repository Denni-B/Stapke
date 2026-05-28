import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final studentSessionProvider = Provider<StudentSession>((ref) => StudentSession());

class StudentSession {
  static String _key(String publicToken) => 'student_name_$publicToken';
  static String _idKey(String publicToken) => 'student_id_$publicToken';

  Future<String?> getName(String publicToken) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key(publicToken))?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<String> getOrCreateStudentId(String publicToken) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_idKey(publicToken))?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4().replaceAll('-', '');
    await prefs.setString(_idKey(publicToken), id);
    return id;
  }

  Future<void> setName(String publicToken, String name) async {
    final trimmed = name.trim();
    if (trimmed.length < 2) {
      throw ArgumentError('Naam moet minstens 2 tekens zijn.');
    }
    if (trimmed.length > 64) {
      throw ArgumentError('Naam mag maximaal 64 tekens zijn.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(publicToken), trimmed);
  }

  Future<void> clearName(String publicToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(publicToken));
  }
}
