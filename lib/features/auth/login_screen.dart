import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _publicTokenController = TextEditingController();

  @override
  void dispose() {
    _publicTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Dennis\'s App',
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/teacher'),
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Doorgaan als spelmaster (a.k.a Denni)'),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Toegang voor Jukkels, Dukkels en sukkels',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _publicTokenController,
                  decoration: const InputDecoration(
                    labelText: 'Spel code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    final String token = _publicTokenController.text.trim();
                    if (token.isEmpty) return;
                    context.go('/class/$token');
                  },
                  icon: const Icon(Icons.school),
                  label: const Text('Spel openen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

