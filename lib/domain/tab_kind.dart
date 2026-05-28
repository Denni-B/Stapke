/// Values stored on [TabCategory.tabKind] in Appwrite.
class TabKind {
  TabKind._();

  static const String cards = 'cards';
  static const String ranking = 'ranking';
  static const String nameVoting = 'name_voting';

  static String normalize(String? raw) {
    final t = raw?.trim();
    if (t == ranking) return ranking;
    if (t == nameVoting) return nameVoting;
    return cards;
  }

  static bool isRanking(String? raw) => normalize(raw) == ranking;

  static bool isNameVoting(String? raw) => normalize(raw) == nameVoting;
}
