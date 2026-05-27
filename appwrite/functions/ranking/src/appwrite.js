import { Client, Databases, ID, Permission, Query, Role } from 'node-appwrite';

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
    classesCollectionId: env('APPWRITE_CLASSES_COLLECTION_ID', 'classes'),
    tabsCollectionId: env('APPWRITE_TABS_COLLECTION_ID', 'tabs'),
    cardsCollectionId: env('APPWRITE_CARDS_COLLECTION_ID', 'cards'),
    rankingSubmissionsCollectionId: env(
      'APPWRITE_RANKING_SUBMISSIONS_COLLECTION_ID',
      'ranking_submissions',
    ),
  };
}

export async function getClassByPublicToken({ databases, publicToken }) {
  const { databaseId, classesCollectionId } = schemaIds();
  const res = await databases.listDocuments(databaseId, classesCollectionId, [
    Query.equal('publicToken', publicToken),
    Query.limit(1),
  ]);
  return res.total > 0 ? res.documents[0] : null;
}

export async function getTab({ databases, tabId }) {
  const { databaseId, tabsCollectionId } = schemaIds();
  try {
    return await databases.getDocument(databaseId, tabsCollectionId, tabId);
  } catch (_) {
    return null;
  }
}

export async function getRankingItem({ databases, rankingItemId }) {
  // NOTE: we store votes per cardId. For a ranking tab, the "items" are normal cards.
  const { databaseId, cardsCollectionId } = schemaIds();
  try {
    return await databases.getDocument(databaseId, cardsCollectionId, rankingItemId);
  } catch (_) {
    return null;
  }
}

export function normalizeTabKind(raw) {
  const t = String(raw ?? '').trim();
  return t === 'ranking' ? 'ranking' : 'cards';
}

export function validateStudentName(name) {
  const trimmed = String(name ?? '').trim();
  if (trimmed.length < 2) return { ok: false, message: 'Naam moet minstens 2 tekens zijn.' };
  if (trimmed.length > 64) return { ok: false, message: 'Naam mag maximaal 64 tekens zijn.' };
  return { ok: true, value: trimmed };
}

export function teacherPermissions(teacherId) {
  return [
    Permission.read(Role.user(teacherId)),
    Permission.update(Role.user(teacherId)),
    Permission.delete(Role.user(teacherId)),
  ];
}

export async function findSubmission({
  databases,
  tabId,
  rankingItemId,
  studentName,
}) {
  const { databaseId, rankingSubmissionsCollectionId } = schemaIds();
  const res = await databases.listDocuments(databaseId, rankingSubmissionsCollectionId, [
    Query.equal('tabId', tabId),
    Query.equal('rankingItemId', rankingItemId),
    Query.equal('studentName', studentName),
    Query.limit(1),
  ]);
  return res.total > 0 ? res.documents[0] : null;
}

export async function upsertSubmission({
  databases,
  teacherId,
  classId,
  tabId,
  rankingItemId,
  studentName,
  score,
  comment,
}) {
  const { databaseId, rankingSubmissionsCollectionId } = schemaIds();
  const now = new Date().toISOString();
  const data = {
    classId,
    tabId,
    rankingItemId,
    studentName,
    score,
    comment: comment ?? '',
    updatedAt: now,
  };

  const existing = await findSubmission({ databases, tabId, rankingItemId, studentName });
  if (existing) {
    return await databases.updateDocument(
      databaseId,
      rankingSubmissionsCollectionId,
      existing.$id,
      data,
    );
  }

  return await databases.createDocument(
    databaseId,
    rankingSubmissionsCollectionId,
    ID.unique(),
    {
      ...data,
      createdAt: now,
    },
    teacherPermissions(teacherId),
  );
}

export async function listMyVotes({ databases, tabId, studentName }) {
  const { databaseId, rankingSubmissionsCollectionId } = schemaIds();
  const res = await databases.listDocuments(databaseId, rankingSubmissionsCollectionId, [
    Query.equal('tabId', tabId),
    Query.equal('studentName', studentName),
    Query.limit(200),
  ]);
  return res.documents.map((d) => ({
    rankingItemId: d.rankingItemId,
    score: d.score,
    comment: d.comment || '',
    updatedAt: d.updatedAt,
  }));
}
