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
    classStudentsCollectionId: env(
      'APPWRITE_CLASS_STUDENTS_COLLECTION_ID',
      'class_students',
    ),
    nameVotesCollectionId: env('APPWRITE_NAME_VOTES_COLLECTION_ID', 'name_votes'),
  };
}

export function validateStudentName(name) {
  const trimmed = String(name ?? '').trim();
  if (trimmed.length < 2) return { ok: false, message: 'Naam moet minstens 2 tekens zijn.' };
  if (trimmed.length > 64) return { ok: false, message: 'Naam mag maximaal 64 tekens zijn.' };
  return { ok: true, value: trimmed };
}

export function validateStudentId(studentId) {
  const trimmed = String(studentId ?? '').trim();
  if (trimmed.length < 4) return { ok: false, message: 'studentId is ongeldig.' };
  if (trimmed.length > 64) return { ok: false, message: 'studentId is te lang.' };
  if (!/^[a-zA-Z0-9_-]+$/.test(trimmed)) {
    return { ok: false, message: 'studentId bevat ongeldige tekens.' };
  }
  return { ok: true, value: trimmed };
}

export function normalizeTabKind(raw) {
  const t = String(raw ?? '').trim();
  if (t === 'ranking') return 'ranking';
  if (t === 'name_voting') return 'name_voting';
  return 'cards';
}

export function teacherPermissions(teacherId) {
  return [
    Permission.read(Role.user(teacherId)),
    Permission.update(Role.user(teacherId)),
    Permission.delete(Role.user(teacherId)),
  ];
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

export async function findClassStudent({ databases, classId, studentId }) {
  const { databaseId, classStudentsCollectionId } = schemaIds();
  const res = await databases.listDocuments(databaseId, classStudentsCollectionId, [
    Query.equal('classId', classId),
    Query.equal('studentId', studentId),
    Query.limit(1),
  ]);
  return res.total > 0 ? res.documents[0] : null;
}

export async function upsertClassStudent({
  databases,
  teacherId,
  classId,
  publicToken,
  studentId,
  name,
}) {
  const { databaseId, classStudentsCollectionId } = schemaIds();
  const now = new Date().toISOString();
  const data = {
    classId,
    publicToken,
    studentId,
    name,
    updatedAt: now,
  };

  const existing = await findClassStudent({ databases, classId, studentId });
  if (existing) {
    return await databases.updateDocument(
      databaseId,
      classStudentsCollectionId,
      existing.$id,
      data,
    );
  }

  return await databases.createDocument(
    databaseId,
    classStudentsCollectionId,
    ID.unique(),
    data,
    teacherPermissions(teacherId),
  );
}

export async function listClassStudents({ databases, classId }) {
  const { databaseId, classStudentsCollectionId } = schemaIds();
  const res = await databases.listDocuments(databaseId, classStudentsCollectionId, [
    Query.equal('classId', classId),
    Query.limit(500),
  ]);
  return res.documents;
}

export async function findNameVote({ databases, tabId, voterStudentId }) {
  const { databaseId, nameVotesCollectionId } = schemaIds();
  const res = await databases.listDocuments(databaseId, nameVotesCollectionId, [
    Query.equal('tabId', tabId),
    Query.equal('voterStudentId', voterStudentId),
    Query.limit(1),
  ]);
  return res.total > 0 ? res.documents[0] : null;
}

export async function upsertNameVote({
  databases,
  teacherId,
  classId,
  publicToken,
  tabId,
  voterStudentId,
  choice1StudentId,
  choice2StudentId,
  choice3StudentId,
}) {
  const { databaseId, nameVotesCollectionId } = schemaIds();
  const now = new Date().toISOString();
  const data = {
    classId,
    publicToken,
    tabId,
    voterStudentId,
    choice1StudentId,
    choice2StudentId,
    choice3StudentId,
    updatedAt: now,
  };
  const existing = await findNameVote({ databases, tabId, voterStudentId });
  if (existing) {
    return await databases.updateDocument(
      databaseId,
      nameVotesCollectionId,
      existing.$id,
      data,
    );
  }
  return await databases.createDocument(
    databaseId,
    nameVotesCollectionId,
    ID.unique(),
    data,
    teacherPermissions(teacherId),
  );
}

export async function listVotesForTab({ databases, tabId }) {
  const { databaseId, nameVotesCollectionId } = schemaIds();
  const res = await databases.listDocuments(databaseId, nameVotesCollectionId, [
    Query.equal('tabId', tabId),
    Query.limit(500),
  ]);
  return res.documents;
}

