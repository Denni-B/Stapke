# Appwrite Function: `ranking`

Public endpoints for student ranking votes (teacher-only storage in Appwrite).

## Routes

- `POST /public/submit` — body: `{ publicToken, rankingItemId, studentName, score, comment? }`
- `POST /public/my-votes` — body: `{ publicToken, tabId, studentName }` → `{ votes: [...] }`

## Environment variables

Same as the drive function:

- `APPWRITE_ENDPOINT`
- `APPWRITE_PROJECT_ID`
- `APPWRITE_API_KEY`
- `APPWRITE_DATABASE_ID` (default `teachers_help`)
- `APPWRITE_CLASSES_COLLECTION_ID`
- `APPWRITE_TABS_COLLECTION_ID`
- `APPWRITE_RANKING_ITEMS_COLLECTION_ID`
- `APPWRITE_RANKING_SUBMISSIONS_COLLECTION_ID`
