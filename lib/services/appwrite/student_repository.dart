import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../domain/models/card_item.dart';
import '../../domain/models/ranking_item.dart';
import '../../domain/models/tab_category.dart';
import '../../domain/models/teachers_class.dart';
import 'appwrite_providers.dart';
import 'schema_ids.dart';

final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  final db = ref.watch(appwriteDatabasesProvider);
  final config = ref.watch(appConfigProvider);
  return StudentRepository(databases: db, schema: SchemaIds.fromConfig(config));
});

class StudentRepository {
  StudentRepository({required this.databases, required this.schema});

  final Databases databases;
  final SchemaIds schema;

  Future<TeachersClass?> getClassByPublicToken(String publicToken) async {
    final models.DocumentList res = await databases.listDocuments(
      databaseId: schema.databaseId,
      collectionId: schema.classesCollectionId,
      queries: <String>[
        Query.equal('publicToken', publicToken),
        Query.limit(1),
      ],
    );
    if (res.total == 0) return null;
    return TeachersClass.fromDoc(res.documents.first.data);
  }

  Future<List<TabCategory>> listTabs(String classId) async {
    final models.DocumentList res = await databases.listDocuments(
      databaseId: schema.databaseId,
      collectionId: schema.tabsCollectionId,
      queries: <String>[
        Query.equal('classId', classId),
        Query.orderAsc('sortOrder'),
      ],
    );
    return res.documents.map((d) => TabCategory.fromDoc(d.data)).toList();
  }

  Future<List<CardItem>> listCards(String tabId) async {
    final models.DocumentList res = await databases.listDocuments(
      databaseId: schema.databaseId,
      collectionId: schema.cardsCollectionId,
      queries: <String>[
        Query.equal('tabId', tabId),
        Query.orderAsc('sortOrder'),
      ],
    );
    return res.documents.map((d) => CardItem.fromDoc(d.data)).toList();
  }

  Future<List<RankingItem>> listRankingItems(String tabId) async {
    final models.DocumentList res = await databases.listDocuments(
      databaseId: schema.databaseId,
      collectionId: schema.rankingItemsCollectionId,
      queries: <String>[
        Query.equal('tabId', tabId),
        Query.orderAsc('sortOrder'),
      ],
    );
    return res.documents.map((d) => RankingItem.fromDoc(d.data)).toList();
  }
}

