import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/appwrite/student_repository.dart';
import '../../services/classroom/classroom_api.dart';
import '../../services/student/student_session.dart';
import 'student_name_screen.dart';
import 'tab_picker_screen.dart';

class StudentHomeScreen extends ConsumerStatefulWidget {
  const StudentHomeScreen({super.key, required this.publicToken});

  final String publicToken;

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  String? _studentName;
  bool _loading = true;
  Object? _error;
  String _className = 'Klas';
  String? _classId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(studentRepositoryProvider);
      final clazz = await repo.getClassByPublicToken(widget.publicToken);
      if (!mounted) return;
      if (clazz == null) {
        setState(() {
          _error = 'Klas niet gevonden.';
          _loading = false;
        });
        return;
      }
      final name = await ref.read(studentSessionProvider).getName(widget.publicToken);
      if (!mounted) return;
      if (name != null && name.trim().isNotEmpty) {
        try {
          final studentId =
              await ref.read(studentSessionProvider).getOrCreateStudentId(widget.publicToken);
          await ref.read(classroomApiProvider).registerStudent(
                publicToken: widget.publicToken,
                classId: clazz.id,
                studentId: studentId,
                name: name,
              );
        } catch (_) {
          // Best effort: keep student flow usable offline / when function is not deployed yet.
        }
      }
      setState(() {
        _className = clazz.name;
        _classId = clazz.id;
        _studentName = name;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onNameDone() {
    ref.read(studentSessionProvider).getName(widget.publicToken).then((name) {
      if (!mounted) return;
      setState(() => _studentName = name);
    });
  }

  Future<void> _changeName() async {
    await ref.read(studentSessionProvider).clearName(widget.publicToken);
    if (!mounted) return;
    setState(() => _studentName = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Klas')),
        body: Center(child: Text('Fout: $_error')),
      );
    }
    final name = _studentName;
    if (name == null || name.isEmpty) {
      return StudentNameScreen(
        publicToken: widget.publicToken,
        className: _className,
        onDone: _onNameDone,
      );
    }
    final classId = _classId;
    if (classId == null) {
      return const Scaffold(
        body: Center(child: Text('Klas niet gevonden.')),
      );
    }
    return TabPickerScreen(
      publicToken: widget.publicToken,
      classId: classId,
      studentName: name,
      className: _className,
      onChangeName: _changeName,
    );
  }
}
