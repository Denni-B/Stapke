import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/class_public_token.dart';
import '../../domain/models/card_item.dart';
import '../../domain/models/ranking_submission.dart';
import '../../domain/models/tab_category.dart';
import '../../domain/models/teachers_class.dart';
import '../../domain/tab_kind.dart';
import '../../utils/tab_color.dart';
import 'appwrite_providers.dart';
import 'schema_ids.dart';

final teacherRepositoryProvider = Provider<TeacherRepository>((ref) {
  final db = ref.watch(appwriteDatabasesProvider);
  final config = ref.watch(appConfigProvider);
  return TeacherRepository(databases: db, schema: SchemaIds.fromConfig(config));
});

class TeacherRepository {
  TeacherRepository({required this.databases, required this.schema});

  final Databases databases;
  final SchemaIds schema;

  Future<List<TeachersClass>> listClasses({required String teacherId}) async {
    final models.DocumentList res = await databases.listDocuments(
      databaseId: schema.databaseId,
      collectionId: schema.classesCollectionId,
      queries: <String>[
        Query.equal('teacherId', teacherId),
        Query.orderAsc('name'),
      ],
    );
    return res.documents.map((d) => TeachersClass.fromDoc(d.data)).toList();
  }

  Future<TeachersClass?> _findClassByPublicToken(String publicToken) async {
    final models.DocumentList res = await databases.listDocuments(
      databaseId: schema.databaseId,
      collectionId: schema.classesCollectionId,
      queries: <String>[
        Query.equal('publicToken', publicToken),
        Query.limit(1),
      ],
    );
    if (res.documents.isEmpty) return null;
    return TeachersClass.fromDoc(res.documents.first.data);
  }

  Future<String> _allocateUniquePublicToken(
    String base, {
    String? ignoreClassDocumentId,
  }) async {
    var candidate = base.isEmpty
        ? const Uuid().v4().replaceAll('-', '')
        : normalizeClassPublicTokenInput(base);
    if (candidate.isEmpty) {
      candidate = const Uuid().v4().replaceAll('-', '');
    }
    for (var attempt = 0; attempt < 100; attempt++) {
      final existing = await _findClassByPublicToken(candidate);
      if (existing == null || existing.id == ignoreClassDocumentId) {
        return candidate;
      }
      final suffix = '_${attempt + 2}';
      var stem = candidate;
      if (stem.length + suffix.length > 64) {
        stem = stem.substring(0, (64 - suffix.length).clamp(1, 64));
      }
      while (stem.endsWith('_')) {
        stem = stem.substring(0, stem.length - 1);
        if (stem.isEmpty) break;
      }
      if (stem.isEmpty) stem = 'c';
      candidate = '$stem$suffix';
      if (candidate.length > 64) candidate = candidate.substring(0, 64);
    }
    return const Uuid().v4().replaceAll('-', '');
  }

  Future<void> _deleteDocumentsWhereAttributeEquals({
    required String collectionId,
    required String attribute,
    required String equalsValue,
  }) async {
    const int limit = 100;
    while (true) {
      final models.DocumentList res = await databases.listDocuments(
        databaseId: schema.databaseId,
        collectionId: collectionId,
        queries: <String>[
          Query.equal(attribute, equalsValue),
          Query.limit(limit),
        ],
      );
      if (res.documents.isEmpty) return;
      for (final models.Document d in res.documents) {
        await databases.deleteDocument(
          databaseId: schema.databaseId,
          collectionId: collectionId,
          documentId: d.$id,
        );
      }
      if (res.documents.length < limit) return;
    }
  }

  Future<TeachersClass> createClass({
    required String teacherId,
    required String name,
    required String teacherNameForToken,
  }) async {
    final base = buildClassPublicToken(
      teacherName: teacherNameForToken,
      className: name,
    );
    final publicToken = await _allocateUniquePublicToken(base);
    final models.Document doc = await databases.createDocument(
      databaseId: schema.databaseId,
      collectionId: schema.classesCollectionId,
      documentId: ID.unique(),
      data: <String, dynamic>{
        'teacherId': teacherId,
        'name': name,
        'publicToken': publicToken,
        'driveFolderId': '',
      },
      permissions: <String>[
        Permission.read(Role.any()),
        Permission.read(Role.user(teacherId)),
        Permission.update(Role.user(teacherId)),
        Permission.delete(Role.user(teacherId)),
      ],
    );
    return TeachersClass.fromDoc(doc.data);
  }

  Future<TeachersClass> updateClassName({
    required String classId,
    required String name,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Klasnaam mag niet leeg zijn.');
    }
    final models.Document doc = await databases.updateDocument(
      databaseId: schema.databaseId,
      collectionId: schema.classesCollectionId,
      documentId: classId,
      data: <String, dynamic>{
        'name': trimmed,
      },
    );
    return TeachersClass.fromDoc(doc.data);
  }

  Future<void> setClassDriveFolderId({required String classId, required String driveFolderId}) async {
    await databases.updateDocument(
      databaseId: schema.databaseId,
      collectionId: schema.classesCollectionId,
      documentId: classId,
      data: <String, dynamic>{'driveFolderId': driveFolderId.trim()},
    );
  }

  Future<void> deleteClassCascade({required String classId}) async {
    final List<TabCategory> tabs = await listTabs(classId: classId);
    for (final TabCategory t in tabs) {
      await deleteTabCascade(tabId: t.id);
    }
    await databases.deleteDocument(
      databaseId: schema.databaseId,
      collectionId: schema.classesCollectionId,
      documentId: classId,
    );
  }

  Future<List<TabCategory>> listTabs({required String classId}) async {
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

  Future<TabCategory> createTab({
    required String teacherId,
    required String classId,
    required String title,
    required int sortOrder,
    String? tabColorHex,
    String tabKind = TabKind.cards,
  }) async {
    final Map<String, dynamic> data = <String, dynamic>{
      'classId': classId,
      'title': title,
      'sortOrder': sortOrder,
      'driveFolderId': '',
      'tabKind': TabKind.normalize(tabKind),
    };
    final String? hex = tabColorHex?.trim();
    if (hex != null && hex.isNotEmpty) {
      final String? normalized = normalizeTabColorHex(hex);
      if (normalized == null || normalized.isEmpty) {
        throw ArgumentError('Ongeldige tabbladkleur. Gebruik een voorinstelling of #RRGGBB.');
      }
      data['tabColorHex'] = normalized;
    }
    final models.Document doc = await databases.createDocument(
      databaseId: schema.databaseId,
      collectionId: schema.tabsCollectionId,
      documentId: ID.unique(),
      data: data,
      permissions: <String>[
        Permission.read(Role.any()),
        Permission.read(Role.user(teacherId)),
        Permission.update(Role.user(teacherId)),
        Permission.delete(Role.user(teacherId)),
      ],
    );
    return TabCategory.fromDoc(doc.data);
  }

  Future<TabCategory> updateTabTitle({
    required String tabId,
    required String title,
  }) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Titel van het tabblad mag niet leeg zijn.');
    }
    final models.Document doc = await databases.updateDocument(
      databaseId: schema.databaseId,
      collectionId: schema.tabsCollectionId,
      documentId: tabId,
      data: <String, dynamic>{
        'title': trimmed,
      },
    );
    return TabCategory.fromDoc(doc.data);
  }

  Future<void> setTabDriveFolderId({required String tabId, required String driveFolderId}) async {
    await databases.updateDocument(
      databaseId: schema.databaseId,
      collectionId: schema.tabsCollectionId,
      documentId: tabId,
      data: <String, dynamic>{'driveFolderId': driveFolderId.trim()},
    );
  }

  Future<TabCategory> updateTabColor({
    required String tabId,
    required String? tabColorHex,
  }) async {
    final String normalized;
    if (tabColorHex == null || tabColorHex.trim().isEmpty) {
      normalized = '';
    } else {
      final String? n = normalizeTabColorHex(tabColorHex.trim());
      if (n == null || n.isEmpty) {
        throw ArgumentError('Ongeldige tabbladkleur. Gebruik een voorinstelling of #RRGGBB.');
      }
      normalized = n;
    }
    final models.Document doc = await databases.updateDocument(
      databaseId: schema.databaseId,
      collectionId: schema.tabsCollectionId,
      documentId: tabId,
      data: <String, dynamic>{
        'tabColorHex': normalized,
      },
    );
    return TabCategory.fromDoc(doc.data);
  }

  Future<void> deleteTabCascade({required String tabId}) async {
    await _deleteDocumentsWhereAttributeEquals(
      collectionId: schema.cardsCollectionId,
      attribute: 'tabId',
      equalsValue: tabId,
    );
    await _deleteDocumentsWhereAttributeEquals(
      collectionId: schema.rankingSubmissionsCollectionId,
      attribute: 'tabId',
      equalsValue: tabId,
    );
    await databases.deleteDocument(
      databaseId: schema.databaseId,
      collectionId: schema.tabsCollectionId,
      documentId: tabId,
    );
  }

  Future<List<RankingSubmission>> listRankingSubmissions({required String tabId}) async {
    final models.DocumentList res = await databases.listDocuments(
      databaseId: schema.databaseId,
      collectionId: schema.rankingSubmissionsCollectionId,
      queries: <String>[
        Query.equal('tabId', tabId),
        Query.limit(500),
      ],
    );
    return res.documents.map((d) => RankingSubmission.fromDoc(d.data)).toList();
  }

  Future<List<CardItem>> listCards({required String tabId}) async {
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

  Future<CardItem> createCard({
    required String teacherId,
    required String tabId,
    required String? title,
    String? cardType,
    String? cardDataJson,
    required String imageDriveFileId,
    required String audioDriveFileId,
    required String imageMimeType,
    required String audioMimeType,
    String? imageAnnotationsJson,
    required int sortOrder,
  }) async {
    if (imageDriveFileId.trim().isEmpty && audioDriveFileId.trim().isEmpty) {
      throw ArgumentError('Kies een afbeelding of audio (minstens één).');
    }
    final type = (cardType == null || cardType.trim().isEmpty)
        ? 'sound_image'
        : cardType.trim();
    final models.Document doc = await databases.createDocument(
      databaseId: schema.databaseId,
      collectionId: schema.cardsCollectionId,
      documentId: ID.unique(),
      data: <String, dynamic>{
        'tabId': tabId,
        'title': title,
        'cardType': type,
        'cardDataJson': (cardDataJson ?? '').trim(),
        'imageDriveFileId': imageDriveFileId,
        'audioDriveFileId': audioDriveFileId,
        'imageMimeType': imageMimeType,
        'audioMimeType': audioMimeType,
        'imageAnnotationsJson': imageAnnotationsJson ?? '',
        'driveFolderId': '',
        'sortOrder': sortOrder,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
      permissions: <String>[
        Permission.read(Role.any()),
        Permission.read(Role.user(teacherId)),
        Permission.update(Role.user(teacherId)),
        Permission.delete(Role.user(teacherId)),
      ],
    );
    return CardItem.fromDoc(doc.data);
  }

  Future<void> setCardDriveFolderId({required String cardId, required String driveFolderId}) async {
    await databases.updateDocument(
      databaseId: schema.databaseId,
      collectionId: schema.cardsCollectionId,
      documentId: cardId,
      data: <String, dynamic>{'driveFolderId': driveFolderId.trim()},
    );
  }

  Future<void> deleteCard({required String cardId}) async {
    await databases.deleteDocument(
      databaseId: schema.databaseId,
      collectionId: schema.cardsCollectionId,
      documentId: cardId,
    );
  }

  Future<void> updateCardSortOrder({
    required String cardId,
    required int sortOrder,
  }) async {
    await databases.updateDocument(
      databaseId: schema.databaseId,
      collectionId: schema.cardsCollectionId,
      documentId: cardId,
      data: <String, dynamic>{
        'sortOrder': sortOrder,
      },
    );
  }

  Future<CardItem> updateCard({
    required String cardId,
    required String? title,
    String? cardType,
    String? cardDataJson,
    required String imageDriveFileId,
    required String audioDriveFileId,
    required String imageMimeType,
    required String audioMimeType,
    String? imageAnnotationsJson,
  }) async {
    if (imageDriveFileId.trim().isEmpty && audioDriveFileId.trim().isEmpty) {
      throw ArgumentError('Kies een afbeelding of audio (minstens één).');
    }
    final type = (cardType == null || cardType.trim().isEmpty)
        ? 'sound_image'
        : cardType.trim();
    final models.Document doc = await databases.updateDocument(
      databaseId: schema.databaseId,
      collectionId: schema.cardsCollectionId,
      documentId: cardId,
      data: <String, dynamic>{
        'title': title,
        'cardType': type,
        'cardDataJson': (cardDataJson ?? '').trim(),
        'imageDriveFileId': imageDriveFileId,
        'audioDriveFileId': audioDriveFileId,
        'imageMimeType': imageMimeType,
        'audioMimeType': audioMimeType,
        'imageAnnotationsJson': imageAnnotationsJson ?? '',
      },
    );
    return CardItem.fromDoc(doc.data);
  }

  Future<TeachersClass> updateClassPublicToken({
    required String classId,
    required String requestedToken,
  }) async {
    final normalized = normalizeClassPublicTokenInput(requestedToken);
    if (normalized.isEmpty) {
      throw ArgumentError('Leerlinglink-token mag niet leeg zijn.');
    }
    final existing = await _findClassByPublicToken(normalized);
    if (existing != null && existing.id != classId) {
      throw StateError(
        'Die leerlinglink wordt al door een andere klas gebruikt. Kies een ander token.',
      );
    }
    final models.Document doc = await databases.updateDocument(
      databaseId: schema.databaseId,
      collectionId: schema.classesCollectionId,
      documentId: classId,
      data: <String, dynamic>{
        'publicToken': normalized,
      },
    );
    return TeachersClass.fromDoc(doc.data);
  }
}

