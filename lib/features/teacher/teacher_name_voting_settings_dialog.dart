import 'package:flutter/material.dart';

Future<List<int>?> showNameVotingSettingsDialog(
  BuildContext context, {
  required List<int> currentWeights,
}) async {
  final controller = TextEditingController(text: currentWeights.join(','));
  final result = await showDialog<List<int>?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Stemming instellingen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('Stemwaarden per keuze (komma-gescheiden).'),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Bijv. 5,2 of 3,2,1',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            autofocus: true,
          ),
          const SizedBox(height: 8),
          Text(
            'Aantal namen dat leerlingen mogen kiezen = aantal waarden.',
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: () {
            final raw = controller.text.trim();
            final parts = raw.split(RegExp(r'[,\s]+')).where((s) => s.trim().isNotEmpty);
            final weights = <int>[];
            for (final p in parts) {
              final v = int.tryParse(p.trim());
              if (v != null && v > 0) weights.add(v);
            }
            if (weights.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Vul minstens één positief getal in.')),
              );
              return;
            }
            if (weights.length > 12) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Maximaal 12 waarden.')),
              );
              return;
            }
            Navigator.of(ctx).pop(weights);
          },
          child: const Text('Opslaan'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

