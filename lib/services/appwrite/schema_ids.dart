import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';

@immutable
class SchemaIds {
  const SchemaIds({
    required this.databaseId,
    required this.classesCollectionId,
    required this.tabsCollectionId,
    required this.cardsCollectionId,
    required this.rankingItemsCollectionId,
    required this.rankingSubmissionsCollectionId,
    required this.driveConnectionsCollectionId,
  });

  factory SchemaIds.fromConfig(AppConfig config) {
    return SchemaIds(
      databaseId: config.appwriteDatabaseId,
      classesCollectionId: config.appwriteClassesCollectionId,
      tabsCollectionId: config.appwriteTabsCollectionId,
      cardsCollectionId: config.appwriteCardsCollectionId,
      rankingItemsCollectionId: config.appwriteRankingItemsCollectionId,
      rankingSubmissionsCollectionId: config.appwriteRankingSubmissionsCollectionId,
      driveConnectionsCollectionId: config.appwriteDriveConnectionsCollectionId,
    );
  }

  final String databaseId;
  final String classesCollectionId;
  final String tabsCollectionId;
  final String cardsCollectionId;
  final String rankingItemsCollectionId;
  final String rankingSubmissionsCollectionId;
  final String driveConnectionsCollectionId;
}

