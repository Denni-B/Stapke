import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/student/student_session.dart';

class StudentNameScreen extends ConsumerStatefulWidget {
  const StudentNameScreen({
    super.key,
    required this.publicToken,
    required this.className,
    required this.onDone,
  });

  final String publicToken;
  final String className;
  final VoidCallback onDone;

  @override
  ConsumerState<StudentNameScreen> createState() => _StudentNameScreenState();
}

class _StudentNameScreenState extends ConsumerState<StudentNameScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul je naam in (minstens 2 tekens).')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(studentSessionProvider).setName(widget.publicToken, name);
      if (!mounted) return;
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.className)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Welkom bij ${widget.className}',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Vul je naam in zodat oppermeester Denni weet wie je bent.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Je naam',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Doorgaan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
