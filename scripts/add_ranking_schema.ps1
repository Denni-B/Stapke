# Adds Ranking support to an existing Teachers Help Appwrite database:
# - tabs.tabKind
# - collections ranking_items + ranking_submissions (with attributes and indexes)
#
# Usage:
#   .\scripts\add_ranking_schema.ps1 -ProjectId "69ca3c3400127827dc8d" -ApiKey "YOUR_SERVER_API_KEY"

param(
  [Parameter(Mandatory = $true)][string]$ProjectId,
  [Parameter(Mandatory = $true)][string]$ApiKey,
  [string]$Endpoint = "https://fra.cloud.appwrite.io/v1",
  [string]$DatabaseId = "teachers_help"
)

$ErrorActionPreference = "Stop"

function Require-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $name. Install: npm i -g appwrite-cli"
  }
}

Require-Command "appwrite"

$env:APPWRITE_ENDPOINT = $Endpoint
$env:APPWRITE_PROJECT_ID = $ProjectId
$env:APPWRITE_API_KEY = $ApiKey

Write-Host "Ranking schema migration on database '$DatabaseId' (project=$ProjectId)..."

Write-Host "-> tabs.tabKind"
appwrite databases create-string-attribute `
  --database-id $DatabaseId `
  --collection-id "tabs" `
  --key "tabKind" `
  --size 32 `
  --required false

cmd /c "appwrite databases get-collection --database-id $DatabaseId --collection-id ranking_items >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  Write-Host "-> collection ranking_items"
  appwrite databases create-collection --database-id $DatabaseId --collection-id "ranking_items" --name "Ranking Items" --document-security true
}

cmd /c "appwrite databases get-collection --database-id $DatabaseId --collection-id ranking_submissions >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  Write-Host "-> collection ranking_submissions"
  appwrite databases create-collection --database-id $DatabaseId --collection-id "ranking_submissions" --name "Ranking Submissions" --document-security true
}

Write-Host "-> collection permissions"
appwrite databases update-collection --database-id $DatabaseId --collection-id "ranking_items" --permissions "read(\"any\")" "read(\"users\")" "create(\"users\")" "update(\"users\")" "delete(\"users\")"
appwrite databases update-collection --database-id $DatabaseId --collection-id "ranking_submissions" --permissions "read(\"users\")" "create(\"users\")" "update(\"users\")" "delete(\"users\")"

Write-Host "-> ranking_items attributes"
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "ranking_items" --key "tabId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "ranking_items" --key "title" --size 128 --required false
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "ranking_items" --key "imageDriveFileId" --size 128 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "ranking_items" --key "imageMimeType" --size 64 --required false
appwrite databases create-integer-attribute --database-id $DatabaseId --collection-id "ranking_items" --key "sortOrder" --required true --min 0 --max 100000
appwrite databases create-index --database-id $DatabaseId --collection-id "ranking_items" --key "byTab" --type "key" --attributes "tabId"
appwrite databases create-index --database-id $DatabaseId --collection-id "ranking_items" --key "byTabAndSort" --type "key" --attributes "tabId" "sortOrder"

Write-Host "-> ranking_submissions attributes"
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

Write-Host ""
Write-Host "Done. In Appwrite Console, wait until new attributes show status 'available' (not building)."
Write-Host "Then deploy the 'ranking' Appwrite function if you have not already."
Write-Host "Redeploy the 'drive' function so ranking photos work for students."
