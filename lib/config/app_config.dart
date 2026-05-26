import 'package:flutter/foundation.dart';

@immutable
class AppConfig {
  const AppConfig({
    required this.appwriteEndpoint,
    required this.appwriteProjectId,
    required this.appwriteDatabaseId,
    required this.appwriteClassesCollectionId,
    required this.appwriteTabsCollectionId,
    required this.appwriteCardsCollectionId,
    required this.appwriteRankingItemsCollectionId,
    required this.appwriteRankingSubmissionsCollectionId,
    required this.appwriteDriveConnectionsCollectionId,
    required this.driveFunctionId,
    required this.rankingFunctionId,
    required this.googleApiKey,
  });

  final String appwriteEndpoint;
  final String appwriteProjectId;

  final String appwriteDatabaseId;
  final String appwriteClassesCollectionId;
  final String appwriteTabsCollectionId;
  final String appwriteCardsCollectionId;
  final String appwriteRankingItemsCollectionId;
  final String appwriteRankingSubmissionsCollectionId;
  final String appwriteDriveConnectionsCollectionId;

  final String driveFunctionId;
  final String rankingFunctionId;
  final String googleApiKey;

  static const AppConfig fromEnv = AppConfig(
    appwriteEndpoint: String.fromEnvironment(
      'APPWRITE_ENDPOINT',
      defaultValue: 'https://fra.cloud.appwrite.io/v1',
    ),
    appwriteProjectId: String.fromEnvironment(
      'APPWRITE_PROJECT_ID',
      defaultValue: '69ca3c3400127827dc8d',
    ),
    appwriteDatabaseId: String.fromEnvironment(
      'APPWRITE_DATABASE_ID',
      defaultValue: 'teachers_help',
    ),
    appwriteClassesCollectionId: String.fromEnvironment(
      'APPWRITE_CLASSES_COLLECTION_ID',
      defaultValue: 'classes',
    ),
    appwriteTabsCollectionId: String.fromEnvironment(
      'APPWRITE_TABS_COLLECTION_ID',
      defaultValue: 'tabs',
    ),
    appwriteCardsCollectionId: String.fromEnvironment(
      'APPWRITE_CARDS_COLLECTION_ID',
      defaultValue: 'cards',
    ),
    appwriteRankingItemsCollectionId: String.fromEnvironment(
      'APPWRITE_RANKING_ITEMS_COLLECTION_ID',
      defaultValue: 'ranking_items',
    ),
    appwriteRankingSubmissionsCollectionId: String.fromEnvironment(
      'APPWRITE_RANKING_SUBMISSIONS_COLLECTION_ID',
      defaultValue: 'ranking_submissions',
    ),
    appwriteDriveConnectionsCollectionId: String.fromEnvironment(
      'APPWRITE_DRIVE_CONNECTIONS_COLLECTION_ID',
      defaultValue: 'drive_connections',
    ),
    driveFunctionId: String.fromEnvironment(
      'APPWRITE_DRIVE_FUNCTION_ID',
      defaultValue: 'drive',
    ),
    rankingFunctionId: String.fromEnvironment(
      'APPWRITE_RANKING_FUNCTION_ID',
      defaultValue: 'ranking',
    ),
    googleApiKey: String.fromEnvironment(
      'GOOGLE_API_KEY',
      defaultValue: '',
    ),
  );
}

