import { Client, Databases, ID, Query } from 'node-appwrite';

import { env } from './env.js';

export function createAdminClient() {
  const client = new Client()
    .setEndpoint(env('APPWRITE_ENDPOINT'))
    .setProject(env('APPWRITE_PROJECT_ID'))
    .setKey(env('APPWRITE_API_KEY'));
  return client;
}

export function createDatabases(client) {
  return new Databases(client);
}

export function schemaIds() {
  return {
    databaseId: env('APPWRITE_DATABASE_ID', 'teachers_help'),
    driveConnectionsCollectionId: env(
      'APPWRITE_DRIVE_CONNECTIONS_COLLECTION_ID',
      'drive_connections',
    ),
    deletedDriveItemsCollectionId: env(
      'APPWRITE_DELETED_DRIVE_ITEMS_COLLECTION_ID',
      'deleted_drive_items',
    ),
    classesCollectionId: env('APPWRITE_CLASSES_COLLECTION_ID', 'classes'),
    tabsCollectionId: env('APPWRITE_TABS_COLLECTION_ID', 'tabs'),
    cardsCollectionId: env('APPWRITE_CARDS_COLLECTION_ID', 'cards'),
  };
}

export async function upsertDriveConnection({
  databases,
  teacherId,
  googleUserId,
  refreshTokenEnc,
}) {
  const { databaseId, driveConnectionsCollectionId } = schemaIds();

  const existing = await databases.listDocuments(
    databaseId,
    driveConnectionsCollectionId,
    [Query.equal('teacherId', teacherId), Query.limit(1)],
  );

  if (existing.total > 0) {
    const doc = existing.documents[0];
    return await databases.updateDocument(
      databaseId,
      driveConnectionsCollectionId,
      doc.$id,
      {
        teacherId,
        googleUserId,
        refreshTokenEnc,
        // Preserve any previously chosen root folder.
        rootFolderId: doc.rootFolderId || '',
      },
    );
  }

  return await databases.createDocument(
    databaseId,
    driveConnectionsCollectionId,
    ID.unique(),
    {
      teacherId,
      googleUserId,
      refreshTokenEnc,
      rootFolderId: '',
    },
  );
}

export async function getDriveConnection({ databases, teacherId }) {
  const { databaseId, driveConnectionsCollectionId } = schemaIds();
  const res = await databases.listDocuments(databaseId, driveConnectionsCollectionId, [
    Query.equal('teacherId', teacherId),
    Query.limit(1),
  ]);
  return res.total > 0 ? res.documents[0] : null;
}

export async function deleteDriveConnections({ databases, teacherId }) {
  const { databaseId, driveConnectionsCollectionId } = schemaIds();
  const res = await databases.listDocuments(databaseId, driveConnectionsCollectionId, [
    Query.equal('teacherId', teacherId),
    Query.limit(100),
  ]);

  let deleted = 0;
  for (const doc of res.documents) {
    await databases.deleteDocument(databaseId, driveConnectionsCollectionId, doc.$id);
    deleted += 1;
  }
  return deleted;
}

export async function getClassByPublicToken({ databases, publicToken }) {
  const { databaseId, classesCollectionId } = schemaIds();
  const res = await databases.listDocuments(databaseId, classesCollectionId, [
    Query.equal('publicToken', publicToken),
    Query.limit(1),
  ]);
  return res.total > 0 ? res.documents[0] : null;
}

export async function classContainsFileId({ databases, classId, fileId }) {
  const { databaseId, tabsCollectionId, cardsCollectionId } = schemaIds();
  const tabs = await databases.listDocuments(databaseId, tabsCollectionId, [
    Query.equal('classId', classId),
    Query.limit(200),
  ]);
  if (tabs.total === 0) return false;

  for (const tab of tabs.documents) {
    const cards = await databases.listDocuments(databaseId, cardsCollectionId, [
      Query.equal('tabId', tab.$id),
      Query.limit(200),
    ]);
    for (const c of cards.documents) {
      if (c.imageDriveFileId === fileId || c.audioDriveFileId === fileId) {
        return true;
      }
    }
  }
  return false;
}

export async function logDeletedDriveItem({
  databases,
  teacherId,
  driveFileId,
  name,
  kind,
}) {
  const { databaseId, deletedDriveItemsCollectionId } = schemaIds();
  return await databases.createDocument(
    databaseId,
    deletedDriveItemsCollectionId,
    ID.unique(),
    {
      teacherId,
      driveFileId,
      name,
      kind,
      deletedAt: new Date().toISOString(),
      restoredAt: '',
    },
  );
}

export async function markDeletedDriveItemRestored({
  databases,
  deletedItemId,
}) {
  const { databaseId, deletedDriveItemsCollectionId } = schemaIds();
  return await databases.updateDocument(
    databaseId,
    deletedDriveItemsCollectionId,
    deletedItemId,
    { restoredAt: new Date().toISOString() },
  );
}

