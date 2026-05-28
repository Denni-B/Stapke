# Appwrite Function: `classroom`

Public endpoints for:
- registering student names per class
- listing registered students
- submitting 3-choice name votes (3-2-1 points)
- teacher results aggregation (requires teacher session)

## Routes

- `POST /public/register-student` — body: `{ publicToken, classId, studentId, name }`
- `POST /public/list-students` — body: `{ publicToken, classId }` → `{ students: [...] }`
- `POST /public/submit-name-vote` — body: `{ publicToken, tabId, voterStudentId, choiceStudentIds: [id1,id2,id3] }`
- `POST /public/my-name-vote` — body: `{ publicToken, tabId, voterStudentId }` → `{ vote: { choiceStudentIds, updatedAt } | null }`
- `POST /teacher/name-vote-results` — body: `{ tabId }` → `{ results: [...] }`

## Environment variables

- `APPWRITE_ENDPOINT`
- `APPWRITE_PROJECT_ID`
- `APPWRITE_API_KEY`
- `APPWRITE_DATABASE_ID` (default `teachers_help`)
- `APPWRITE_CLASSES_COLLECTION_ID` (default `classes`)
- `APPWRITE_TABS_COLLECTION_ID` (default `tabs`)
- `APPWRITE_CLASS_STUDENTS_COLLECTION_ID` (default `class_students`)
- `APPWRITE_NAME_VOTES_COLLECTION_ID` (default `name_votes`)

