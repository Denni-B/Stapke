/// Values stored on [TabCategory.tabKind] in Appwrite.
class TabKind {
  TabKind._();

  static const String cards = 'cards';
  static const String ranking = 'ranking';

  static String normalize(String? raw) {
    final t = raw?.trim();
    if (t == ranking) return ranking;
    return cards;
  }

  static bool isRanking(String? raw) => normalize(raw) == ranking;
}
