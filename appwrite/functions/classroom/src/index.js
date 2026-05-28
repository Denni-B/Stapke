import {
  createAdminClient,
  createDatabases,
  getClassByPublicToken,
  getTab,
  listClassStudents,
  listVotesForTab,
  normalizeTabKind,
  upsertClassStudent,
  upsertNameVote,
  validateStudentId,
  validateStudentName,
} from './appwrite.js';

function json(res, status, body) {
  return res.json(body, status);
}

function parseBodyJson(req) {
  if (req.bodyJson && typeof req.bodyJson === 'object') return req.bodyJson;
  const raw = req.body;
  if (!raw) return null;
  if (typeof raw === 'object') return raw;
  if (typeof raw !== 'string') return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

function parseWeightsFromTab(tab) {
  const raw = String(tab?.nameVotingWeightsJson ?? '').trim();
  if (!raw) return [3, 2, 1];
  try {
    const decoded = JSON.parse(raw);
    if (!Array.isArray(decoded)) return [3, 2, 1];
    const weights = decoded
      .map((x) => Number(x))
      .filter((n) => Number.isFinite(n))
      .map((n) => Math.trunc(n))
      .filter((n) => n > 0);
    return weights.length > 0 ? weights : [3, 2, 1];
  } catch (_) {
    return [3, 2, 1];
  }
}

function toPoints(choiceIndex, weights) {
  if (!Array.isArray(weights) || weights.length === 0) return 0;
  return weights[choiceIndex] ?? 0;
}

export default async ({ req, res, log, error }) => {
  try {
    const path = req.path || '/';
    const body = parseBodyJson(req) || {};

    // POST /public/register-student
    if (req.method === 'POST' && path === '/public/register-student') {
      const { publicToken, classId, studentId, name } = body;
      if (!publicToken || !classId || !studentId) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: 'Missing publicToken/classId/studentId.',
        });
      }
      const nameCheck = validateStudentName(name);
      if (!nameCheck.ok) {
        return json(res, 400, { error: 'BAD_REQUEST', message: nameCheck.message });
      }
      const idCheck = validateStudentId(studentId);
      if (!idCheck.ok) {
        return json(res, 400, { error: 'BAD_REQUEST', message: idCheck.message });
      }

      const client = createAdminClient();
      const databases = createDatabases(client);

      const clazz = await getClassByPublicToken({ databases, publicToken });
      if (!clazz || clazz.$id !== classId) {
        return json(res, 404, { error: 'NOT_FOUND', message: 'Class not found.' });
      }
      const teacherId = clazz.teacherId;
      if (!teacherId) {
        return json(res, 500, { error: 'INTERNAL', message: 'Missing teacherId on class.' });
      }

      const doc = await upsertClassStudent({
        databases,
        teacherId,
        classId: clazz.$id,
        publicToken,
        studentId: idCheck.value,
        name: nameCheck.value,
      });

      return json(res, 200, { ok: true, studentDocId: doc.$id, updatedAt: doc.updatedAt });
    }

    // POST /public/list-students
    if (req.method === 'POST' && path === '/public/list-students') {
      const { publicToken, classId } = body;
      if (!publicToken || !classId) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: 'Missing publicToken/classId.',
        });
      }

      const client = createAdminClient();
      const databases = createDatabases(client);

      const clazz = await getClassByPublicToken({ databases, publicToken });
      if (!clazz || clazz.$id !== classId) {
        return json(res, 404, { error: 'NOT_FOUND', message: 'Class not found.' });
      }

      const docs = await listClassStudents({ databases, classId: clazz.$id });
      const students = docs
        .map((d) => ({
          studentId: d.studentId,
          name: d.name,
          updatedAt: d.updatedAt,
        }))
        .filter((s) => s.studentId && s.name);

      // Stable ordering for UX.
      students.sort((a, b) =>
        String(a.name || '').localeCompare(String(b.name || ''), 'nl', { sensitivity: 'base' }),
      );

      return json(res, 200, { students });
    }

    // POST /public/submit-name-vote
    if (req.method === 'POST' && path === '/public/submit-name-vote') {
      const { publicToken, tabId, voterStudentId, choiceStudentIds } = body;
      if (!publicToken || !tabId || !voterStudentId) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: 'Missing publicToken/tabId/voterStudentId.',
        });
      }
      const voterCheck = validateStudentId(voterStudentId);
      if (!voterCheck.ok) {
        return json(res, 400, { error: 'BAD_REQUEST', message: voterCheck.message });
      }
      const choices = Array.isArray(choiceStudentIds) ? choiceStudentIds : [];
      const normalizedChoices = choices
        .map((x) => String(x ?? '').trim())
        .filter((x) => x !== '');

      for (const id of normalizedChoices) {
        const check = validateStudentId(id);
        if (!check.ok) {
          return json(res, 400, { error: 'BAD_REQUEST', message: 'Ongeldige keuze.' });
        }
      }

      const client = createAdminClient();
      const databases = createDatabases(client);

      const tab = await getTab({ databases, tabId });
      if (!tab) {
        return json(res, 404, { error: 'NOT_FOUND', message: 'Tab not found.' });
      }
      if (normalizeTabKind(tab.tabKind) !== 'name_voting') {
        return json(res, 403, { error: 'FORBIDDEN', message: 'Not a name voting tab.' });
      }

      const weights = parseWeightsFromTab(tab);

      if (normalizedChoices.length !== weights.length) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: `Kies precies ${weights.length} naam/namen.`,
        });
      }
      const unique = new Set(normalizedChoices);
      if (unique.size !== weights.length) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: `Kies ${weights.length} verschillende namen.`,
        });
      }

      const clazz = await getClassByPublicToken({ databases, publicToken });
      if (!clazz || clazz.$id !== tab.classId) {
        return json(res, 403, { error: 'FORBIDDEN', message: 'Tab not part of this class.' });
      }

      const teacherId = clazz.teacherId;
      if (!teacherId) {
        return json(res, 500, { error: 'INTERNAL', message: 'Missing teacherId on class.' });
      }

      // Prevent self-voting (optional safety). If desired, remove this.
      if (unique.has(voterCheck.value)) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: 'Je kunt niet op jezelf stemmen.',
        });
      }

      const doc = await upsertNameVote({
        databases,
        teacherId,
        classId: clazz.$id,
        publicToken,
        tabId: tab.$id,
        voterStudentId: voterCheck.value,
        choice1StudentId: normalizedChoices[0],
        choice2StudentId: normalizedChoices[1] ?? '',
        choice3StudentId: normalizedChoices[2] ?? '',
      });

      return json(res, 200, { ok: true, voteId: doc.$id, updatedAt: doc.updatedAt });
    }

    // POST /public/my-name-vote
    if (req.method === 'POST' && path === '/public/my-name-vote') {
      const { publicToken, tabId, voterStudentId } = body;
      if (!publicToken || !tabId || !voterStudentId) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: 'Missing publicToken/tabId/voterStudentId.',
        });
      }
      const voterCheck = validateStudentId(voterStudentId);
      if (!voterCheck.ok) {
        return json(res, 400, { error: 'BAD_REQUEST', message: voterCheck.message });
      }

      const client = createAdminClient();
      const databases = createDatabases(client);

      const tab = await getTab({ databases, tabId });
      if (!tab) {
        return json(res, 404, { error: 'NOT_FOUND', message: 'Tab not found.' });
      }
      if (normalizeTabKind(tab.tabKind) !== 'name_voting') {
        return json(res, 403, { error: 'FORBIDDEN', message: 'Not a name voting tab.' });
      }

      const weights = parseWeightsFromTab(tab);

      const clazz = await getClassByPublicToken({ databases, publicToken });
      if (!clazz || clazz.$id !== tab.classId) {
        return json(res, 403, { error: 'FORBIDDEN', message: 'Tab not part of this class.' });
      }

      // The vote docs are teacher-only, so we need admin client anyway.
      const votes = await listVotesForTab({ databases, tabId: tab.$id });
      const mine = votes.find((v) => String(v.voterStudentId) === voterCheck.value) || null;
      if (!mine) return json(res, 200, { vote: null });

      const choices = [mine.choice1StudentId, mine.choice2StudentId, mine.choice3StudentId]
        .map((x) => String(x ?? '').trim())
        .filter((x) => x !== '')
        .slice(0, weights.length);

      return json(res, 200, {
        vote: {
          choiceStudentIds: choices,
          updatedAt: mine.updatedAt,
        },
      });
    }

    // POST /teacher/name-vote-results
    if (req.method === 'POST' && path === '/teacher/name-vote-results') {
      const { tabId } = body;
      if (!tabId) {
        return json(res, 400, { error: 'BAD_REQUEST', message: 'Missing tabId.' });
      }

      const teacherUserId =
        req.headers?.['x-appwrite-user-id'] ||
        req.headers?.['X-Appwrite-User-Id'] ||
        null;
      if (!teacherUserId) {
        return json(res, 401, {
          error: 'UNAUTHORIZED',
          message: 'Teacher session required.',
        });
      }

      const client = createAdminClient();
      const databases = createDatabases(client);

      const tab = await getTab({ databases, tabId });
      if (!tab) {
        return json(res, 404, { error: 'NOT_FOUND', message: 'Tab not found.' });
      }
      if (normalizeTabKind(tab.tabKind) !== 'name_voting') {
        return json(res, 403, { error: 'FORBIDDEN', message: 'Not a name voting tab.' });
      }

      const weights = parseWeightsFromTab(tab);

      // Need class to check teacher ownership. We don't have token here; read class by id.
      // We can list by id using admin key (safe).
      const clazz = await (async () => {
        // Inline minimal: query classes where $id matches is not supported; use getDocument.
        // But we don't have collection ids here; use helper by token? Not possible.
        // Instead, fetch class via list on classId attribute from tab.
        // (Most Appwrite setups allow getDocument by id; we implement a tiny helper here.)
        const { databaseId, classesCollectionId } = (await import('./appwrite.js')).schemaIds();
        try {
          return await databases.getDocument(databaseId, classesCollectionId, tab.classId);
        } catch (_) {
          return null;
        }
      })();

      if (!clazz) {
        return json(res, 404, { error: 'NOT_FOUND', message: 'Class not found.' });
      }
      if (String(clazz.teacherId) !== String(teacherUserId)) {
        return json(res, 403, { error: 'FORBIDDEN', message: 'Not your class.' });
      }

      const students = await listClassStudents({ databases, classId: clazz.$id });
      const nameById = new Map();
      for (const s of students) {
        if (s.studentId && s.name) nameById.set(String(s.studentId), String(s.name));
      }

      const votes = await listVotesForTab({ databases, tabId: tab.$id });
      const pointsByStudentId = new Map();
      for (const v of votes) {
        const choices = [v.choice1StudentId, v.choice2StudentId, v.choice3StudentId].map((x) =>
          String(x ?? '').trim(),
        );
        for (let i = 0; i < choices.length; i++) {
          const id = choices[i];
          if (!id) continue;
          const prev = pointsByStudentId.get(id) || 0;
          pointsByStudentId.set(id, prev + toPoints(i, weights));
        }
      }

      const results = Array.from(pointsByStudentId.entries()).map(([studentId, pointsTotal]) => ({
        studentId,
        name: nameById.get(studentId) || '(onbekend)',
        pointsTotal,
      }));
      results.sort((a, b) => b.pointsTotal - a.pointsTotal);

      return json(res, 200, { results });
    }

    return json(res, 404, { error: 'NOT_FOUND', message: `No route for ${req.method} ${path}` });
  } catch (e) {
    error(e?.stack || String(e));
    return json(res, 500, { error: 'INTERNAL', message: String(e) });
  }
};

