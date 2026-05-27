import 'dart:convert';

class CardTypeIds {
  static const String soundImage = 'sound_image';
  static const String imageFillIn = 'image_fill_in';
  static const String ranking = 'ranking';
}

class CardTypeOption {
  const CardTypeOption({required this.id, required this.label});
  final String id;
  final String label;
}

class CardTypeRegistry {
  static const List<CardTypeOption> teacherOptions = <CardTypeOption>[
    CardTypeOption(id: CardTypeIds.soundImage, label: 'Geluidskaart'),
    CardTypeOption(id: CardTypeIds.imageFillIn, label: 'Afbeelding + invulwoord'),
    CardTypeOption(id: CardTypeIds.ranking, label: 'Ranking kaart'),
  ];

  static String normalizeType(String? raw) {
    final t = raw?.trim();
    return (t == null || t.isEmpty) ? CardTypeIds.soundImage : t;
  }
}

class ImageFillInCardData {
  const ImageFillInCardData({
    required this.prompt,
    required this.acceptedAnswers,
  });

  final String prompt;
  final List<String> acceptedAnswers;

  static const int currentVersion = 1;

  static ImageFillInCardData? tryDecode(String? json) {
    final raw = json?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final promptAny = map['prompt'];
      final answersAny = map['answers'];
      if (promptAny is! String) return null;
      final answers = <String>[];
      if (answersAny is List) {
        for (final a in answersAny) {
          if (a is String && a.trim().isNotEmpty) answers.add(a.trim());
        }
      }
      return ImageFillInCardData(prompt: promptAny.trim(), acceptedAnswers: answers);
    } catch (_) {
      return null;
    }
  }

  String encode() {
    return jsonEncode(<String, dynamic>{
      'v': currentVersion,
      'prompt': prompt,
      'answers': acceptedAnswers,
    });
  }
}

String normalizeAnswer(String input) {
  final trimmed = input.trim().toLowerCase();
  return trimmed.replaceAll(RegExp(r'\\s+'), ' ');
}

List<String> parseAcceptedAnswersCsv(String input) {
  final parts = input
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  // Deduplicate (case-insensitive) but preserve original casing for display.
  final seen = <String>{};
  final out = <String>[];
  for (final p in parts) {
    final key = normalizeAnswer(p);
    if (key.isEmpty) continue;
    if (seen.add(key)) out.add(p);
  }
  return out;
}

