import {
  createAdminClient,
  createDatabases,
  getClassByPublicToken,
  getRankingItem,
  getTab,
  listMyVotes,
  normalizeTabKind,
  upsertSubmission,
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

export default async ({ req, res, log, error }) => {
  try {
    const path = req.path || '/';
    const body = parseBodyJson(req) || {};

    // POST /public/submit
    if (req.method === 'POST' && path === '/public/submit') {
      const { publicToken, rankingItemId, studentName, score, comment } = body;
      if (!publicToken || !rankingItemId) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: 'Missing publicToken/rankingItemId.',
        });
      }

      const nameCheck = validateStudentName(studentName);
      if (!nameCheck.ok) {
        return json(res, 400, { error: 'BAD_REQUEST', message: nameCheck.message });
      }

      const scoreNum = Number(score);
      if (!Number.isInteger(scoreNum) || scoreNum < 1 || scoreNum > 10) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: 'Score moet een geheel getal tussen 1 en 10 zijn.',
        });
      }

      const commentStr =
        comment == null || String(comment).trim() === ''
          ? ''
          : String(comment).trim().slice(0, 500);

      const client = createAdminClient();
      const databases = createDatabases(client);

      const clazz = await getClassByPublicToken({ databases, publicToken });
      if (!clazz) {
        return json(res, 404, { error: 'NOT_FOUND', message: 'Class not found.' });
      }

      const item = await getRankingItem({ databases, rankingItemId });
      if (!item || item.tabId == null) {
        return json(res, 404, { error: 'NOT_FOUND', message: 'Ranking item not found.' });
      }

      const tab = await getTab({ databases, tabId: item.tabId });
      if (!tab || tab.classId !== clazz.$id) {
        return json(res, 403, { error: 'FORBIDDEN', message: 'Item not part of this class.' });
      }

      if (normalizeTabKind(tab.tabKind) !== 'ranking') {
        return json(res, 403, { error: 'FORBIDDEN', message: 'Not a ranking tab.' });
      }

      const teacherId = clazz.teacherId;
      if (!teacherId) {
        return json(res, 500, { error: 'INTERNAL', message: 'Missing teacherId on class.' });
      }

      const doc = await upsertSubmission({
        databases,
        teacherId,
        classId: clazz.$id,
        tabId: item.tabId,
        rankingItemId,
        studentName: nameCheck.value,
        score: scoreNum,
        comment: commentStr,
      });

      return json(res, 200, {
        ok: true,
        submissionId: doc.$id,
        updated: doc.updatedAt,
      });
    }

    // POST /public/my-votes
    if (req.method === 'POST' && path === '/public/my-votes') {
      const { publicToken, tabId, studentName } = body;
      if (!publicToken || !tabId) {
        return json(res, 400, {
          error: 'BAD_REQUEST',
          message: 'Missing publicToken/tabId.',
        });
      }

      const nameCheck = validateStudentName(studentName);
      if (!nameCheck.ok) {
        return json(res, 400, { error: 'BAD_REQUEST', message: nameCheck.message });
      }

      const client = createAdminClient();
      const databases = createDatabases(client);

      const clazz = await getClassByPublicToken({ databases, publicToken });
      if (!clazz) {
        return json(res, 404, { error: 'NOT_FOUND', message: 'Class not found.' });
      }

      const tab = await getTab({ databases, tabId });
      if (!tab || tab.classId !== clazz.$id) {
        return json(res, 403, { error: 'FORBIDDEN', message: 'Tab not part of this class.' });
      }

      if (normalizeTabKind(tab.tabKind) !== 'ranking') {
        return json(res, 403, { error: 'FORBIDDEN', message: 'Not a ranking tab.' });
      }

      const votes = await listMyVotes({
        databases,
        tabId,
        studentName: nameCheck.value,
      });

      return json(res, 200, { votes });
    }

    return json(res, 404, { error: 'NOT_FOUND', message: `No route for ${req.method} ${path}` });
  } catch (e) {
    error(e?.stack || String(e));
    return json(res, 500, { error: 'INTERNAL', message: String(e) });
  }
};
