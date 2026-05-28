import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/appwrite/student_repository.dart';
import '../../services/classroom/classroom_api.dart';
import '../../services/student/student_session.dart';
import '../../utils/tab_color.dart';

class NameVotingViewerScreen extends ConsumerStatefulWidget {
  const NameVotingViewerScreen({
    super.key,
    required this.publicToken,
    required this.classId,
    required this.tabId,
    required this.tabTitle,
    this.tabColorHex,
  });

  final String publicToken;
  final String classId;
  final String tabId;
  final String tabTitle;
  final String? tabColorHex;

  @override
  ConsumerState<NameVotingViewerScreen> createState() => _NameVotingViewerScreenState();
}

class _NameVotingViewerScreenState extends ConsumerState<NameVotingViewerScreen> {
  bool _loading = true;
  Object? _error;

  String? _studentId;
  List<ClassroomStudent> _students = const <ClassroomStudent>[];
  List<int> _weights = const <int>[3, 2, 1];

  /// Ordered selection by rank; points are defined by `_weights`.
  final List<String> _selected = <String>[];
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _submitted = false;
    });
    try {
      final studentId =
          await ref.read(studentSessionProvider).getOrCreateStudentId(widget.publicToken);
      final tab = await ref.read(studentRepositoryProvider).getTab(widget.tabId);
      final weights = (tab?.nameVotingWeights ?? const <int>[3, 2, 1])
          .where((w) => w > 0)
          .toList();
      final api = ref.read(classroomApiProvider);
      final students = await api.listStudents(
        publicToken: widget.publicToken,
        classId: widget.classId,
      );
      final myVote = await api.fetchMyNameVote(
        publicToken: widget.publicToken,
        tabId: widget.tabId,
        voterStudentId: studentId,
      );
      if (!mounted) return;
      setState(() {
        _studentId = studentId;
        _students = students;
        _weights = weights.isEmpty ? const <int>[3, 2, 1] : weights;
        _selected
          ..clear()
          ..addAll(myVote?.choiceStudentIds ?? const <String>[]);
        // Trim previous votes if teacher reduced allowed choices.
        if (_selected.length > _weights.length) {
          _selected.removeRange(_weights.length, _selected.length);
        }
        _submitted = myVote != null;
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

  void _togglePick(String pickedStudentId) {
    final myId = _studentId;
    if (myId != null && pickedStudentId == myId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Je kunt niet op jezelf stemmen.')),
      );
      return;
    }
    setState(() {
      _submitted = false; // selection changed; not yet stored
      final idx = _selected.indexOf(pickedStudentId);
      if (idx >= 0) {
        _selected.removeAt(idx);
        return;
      }
      if (_selected.length >= _weights.length) {
        _selected.removeLast();
      }
      _selected.add(pickedStudentId);
    });
  }

  String _ordinalNl(int idx1) => switch (idx1) {
        1 => '1e',
        2 => '2e',
        3 => '3e',
        _ => '${idx1}e',
      };

  String _rankLabel(int idx) {
    final w = (idx >= 0 && idx < _weights.length) ? _weights[idx] : 0;
    return '${_ordinalNl(idx + 1)} (${w}p)';
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final voterId = _studentId;
    if (voterId == null) return;
    if (_selected.length != _weights.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kies ${_weights.length} verschillende namen.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(classroomApiProvider).submitNameVote(
            publicToken: widget.publicToken,
            tabId: widget.tabId,
            voterStudentId: voterId,
            choiceStudentIds: List<String>.from(_selected),
          );
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stem opgeslagen.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opslaan mislukt: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color? accent = parseTabColorHex(widget.tabColorHex);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tabTitle),
        backgroundColor: accent,
        foregroundColor: accent != null ? foregroundOnTabColor(accent) : null,
        actions: <Widget>[
          IconButton(
            tooltip: 'Vernieuwen',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text('Fout: $_error'));
    }
    if (_students.isEmpty) {
      return const Center(child: Text('Nog geen namen in deze klas.'));
    }

    final byId = <String, ClassroomStudent>{
      for (final s in _students) s.studentId: s,
    };

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Kies ${_weights.length} namen',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Je mag ${_weights.length} naam/namen kiezen. '
                  'Punten per keuze: ${_weights.join(', ')}. '
                  'Je stem wordt pas opgeslagen als je op “Stemmen” drukt.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (_submitted) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Je stem is opgeslagen — je kunt hem aanpassen en opnieuw opslaan.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List<Widget>.generate(_weights.length, (i) {
                final id = i < _selected.length ? _selected[i] : null;
                final name = id == null ? '—' : (byId[id]?.name ?? '(onbekend)');
                return Chip(
                  label: Text('${_rankLabel(i)}: $name'),
                  onDeleted: id == null
                      ? null
                      : () {
                          setState(() {
                            _selected.remove(id);
                            _submitted = false;
                          });
                        },
                );
              }),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _students.length,
              itemBuilder: (context, index) {
                final s = _students[index];
                final idx = _selected.indexOf(s.studentId);
                final bool selected = idx >= 0;
                final String? trailingLabel = selected ? _rankLabel(idx) : null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.tonal(
                    onPressed: _submitting ? null : () => _togglePick(s.studentId),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      backgroundColor: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      foregroundColor: selected
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : null,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (trailingLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(
                              trailingLabel,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Stemmen'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

