param(
  [Parameter(Mandatory = $true)][string]$ProjectId,
  [Parameter(Mandatory = $true)][string]$ApiKey,
  [string]$Endpoint = "https://cloud.appwrite.io/v1",
  [string]$DatabaseId = "teachers_help"
)

$ErrorActionPreference = "Stop"

function Require-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $name"
  }
}

Require-Command "appwrite"

Write-Host "Using endpoint=$Endpoint project=$ProjectId db=$DatabaseId"

# Configure environment for the Appwrite CLI.
$env:APPWRITE_ENDPOINT = $Endpoint
$env:APPWRITE_PROJECT_ID = $ProjectId
$env:APPWRITE_API_KEY = $ApiKey

# Database
cmd /c "appwrite databases get --database-id $DatabaseId >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  appwrite databases create --database-id $DatabaseId --name "Teachers Help"
}

# Collections
cmd /c "appwrite databases get-collection --database-id $DatabaseId --collection-id classes >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  appwrite databases create-collection --database-id $DatabaseId --collection-id "classes" --name "Classes" --document-security true
}
cmd /c "appwrite databases get-collection --database-id $DatabaseId --collection-id tabs >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  appwrite databases create-collection --database-id $DatabaseId --collection-id "tabs" --name "Tabs" --document-security true
}
cmd /c "appwrite databases get-collection --database-id $DatabaseId --collection-id cards >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  appwrite databases create-collection --database-id $DatabaseId --collection-id "cards" --name "Cards" --document-security true
}
cmd /c "appwrite databases get-collection --database-id $DatabaseId --collection-id drive_connections >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  appwrite databases create-collection --database-id $DatabaseId --collection-id "drive_connections" --name "Drive Connections" --document-security true
}
cmd /c "appwrite databases get-collection --database-id $DatabaseId --collection-id deleted_drive_items >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  appwrite databases create-collection --database-id $DatabaseId --collection-id "deleted_drive_items" --name "Deleted Drive Items" --document-security true
}
cmd /c "appwrite databases get-collection --database-id $DatabaseId --collection-id ranking_submissions >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  appwrite databases create-collection --database-id $DatabaseId --collection-id "ranking_submissions" --name "Ranking Submissions" --document-security true
}

# Collection permissions
# NOTE: `document-security true` is enabled, but Appwrite still requires
# collection-level create permission for client SDK writes.
# - tabs: students list tabs, teacher manages tabs
appwrite databases update-collection --database-id $DatabaseId --collection-id "tabs" --permissions "read(\"any\")" "read(\"users\")" "create(\"users\")" "update(\"users\")" "delete(\"users\")"
# - cards: students list cards, teacher manages cards
appwrite databases update-collection --database-id $DatabaseId --collection-id "cards" --permissions "read(\"any\")" "read(\"users\")" "create(\"users\")" "update(\"users\")" "delete(\"users\")"
# - ranking_submissions: teacher-only data (writes via Appwrite Function with API key)
appwrite databases update-collection --database-id $DatabaseId --collection-id "ranking_submissions" --permissions "read(\"users\")" "create(\"users\")" "update(\"users\")" "delete(\"users\")"

# Attributes and indexes
# classes
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "classes" --key "teacherId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "classes" --key "name" --size 128 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "classes" --key "publicToken" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "classes" --key "driveFolderId" --size 128 --required false
appwrite databases create-index --database-id $DatabaseId --collection-id "classes" --key "byTeacher" --type "key" --attributes "teacherId"
appwrite databases create-index --database-id $DatabaseId --collection-id "classes" --key "byPublicToken" --type "unique" --attributes "publicToken"

# tabs
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "tabs" --key "classId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "tabs" --key "title" --size 128 --required true
appwrite databases create-integer-attribute --database-id $DatabaseId --collection-id "tabs" --key "sortOrder" --required true --min 0 --max 100000
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "tabs" --key "tabColorHex" --size 16 --required false
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "tabs" --key "driveFolderId" --size 128 --required false
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "tabs" --key "tabKind" --size 32 --required false
appwrite databases create-index --database-id $DatabaseId --collection-id "tabs" --key "byClass" --type "key" --attributes "classId"
appwrite databases create-index --database-id $DatabaseId --collection-id "tabs" --key "byClassAndSort" --type "key" --attributes "classId" "sortOrder"

# cards
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "cards" --key "tabId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "cards" --key "title" --size 128 --required false
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "cards" --key "imageDriveFileId" --size 128 --required false
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "cards" --key "audioDriveFileId" --size 128 --required false
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "cards" --key "imageMimeType" --size 64 --required false
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "cards" --key "audioMimeType" --size 64 --required false
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "cards" --key "imageAnnotationsJson" --size 20000 --required false
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "cards" --key "driveFolderId" --size 128 --required false
appwrite databases create-integer-attribute --database-id $DatabaseId --collection-id "cards" --key "sortOrder" --required true --min 0 --max 100000
appwrite databases create-datetime-attribute --database-id $DatabaseId --collection-id "cards" --key "createdAt" --required true
appwrite databases create-index --database-id $DatabaseId --collection-id "cards" --key "byTab" --type "key" --attributes "tabId"
appwrite databases create-index --database-id $DatabaseId --collection-id "cards" --key "byTabAndSort" --type "key" --attributes "tabId" "sortOrder"

# drive_connections
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "drive_connections" --key "teacherId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "drive_connections" --key "googleUserId" --size 128 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "drive_connections" --key "refreshTokenEnc" --size 4096 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "drive_connections" --key "rootFolderId" --size 128 --required false
appwrite databases create-index --database-id $DatabaseId --collection-id "drive_connections" --key "byTeacher" --type "unique" --attributes "teacherId"

# deleted_drive_items
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "deleted_drive_items" --key "teacherId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "deleted_drive_items" --key "driveFileId" --size 128 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "deleted_drive_items" --key "name" --size 256 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "deleted_drive_items" --key "kind" --size 64 --required true
appwrite databases create-datetime-attribute --database-id $DatabaseId --collection-id "deleted_drive_items" --key "deletedAt" --required true
appwrite databases create-datetime-attribute --database-id $DatabaseId --collection-id "deleted_drive_items" --key "restoredAt" --required false
appwrite databases create-index --database-id $DatabaseId --collection-id "deleted_drive_items" --key "byTeacherAndDeletedAt" --type "key" --attributes "teacherId" "deletedAt"

# ranking_submissions
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "ranking_submissions" --key "classId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "ranking_submissions" --key "tabId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "ranking_submissions" --key "rankingItemId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "ranking_submissions" --key "studentName" --size 64 --required true
appwrite databases create-integer-attribute --database-id $DatabaseId --collection-id "ranking_submissions" --key "score" --required true --min 1 --max 10
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "ranking_submissions" --key "comment" --size 500 --required false
appwrite databases create-datetime-attribute --database-id $DatabaseId --collection-id "ranking_submissions" --key "createdAt" --required true
appwrite databases create-datetime-attribute --database-id $DatabaseId --collection-id "ranking_submissions" --key "updatedAt" --required true
appwrite databases create-index --database-id $DatabaseId --collection-id "ranking_submissions" --key "byTab" --type "key" --attributes "tabId"
appwrite databases create-index --database-id $DatabaseId --collection-id "ranking_submissions" --key "byTabStudentItem" --type "key" --attributes "tabId" "studentName" "rankingItemId"

Write-Host "Done. Next: configure permissions per-doc for public student link access."

