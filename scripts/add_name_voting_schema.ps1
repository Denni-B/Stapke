# Adds Name Voting support to an existing Teachers Help Appwrite database:
# - collection class_students (student registry per class)
# - collection name_votes (3-choice ballots per tab)
#
# Usage:
#   .\scripts\add_name_voting_schema.ps1 -ProjectId "..." -ApiKey "YOUR_SERVER_API_KEY"

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

Write-Host "Name voting schema migration on database '$DatabaseId' (project=$ProjectId)..."

Write-Host "-> tabs.nameVotingWeightsJson"
appwrite databases create-string-attribute `
  --database-id $DatabaseId `
  --collection-id "tabs" `
  --key "nameVotingWeightsJson" `
  --size 200 `
  --required false

cmd /c "appwrite databases get-collection --database-id $DatabaseId --collection-id class_students >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  Write-Host "-> collection class_students"
  appwrite databases create-collection --database-id $DatabaseId --collection-id "class_students" --name "Class Students" --document-security true
}

cmd /c "appwrite databases get-collection --database-id $DatabaseId --collection-id name_votes >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
  Write-Host "-> collection name_votes"
  appwrite databases create-collection --database-id $DatabaseId --collection-id "name_votes" --name "Name Votes" --document-security true
}

Write-Host "-> collection permissions"
appwrite databases update-collection --database-id $DatabaseId --collection-id "class_students" --permissions "read(\"users\")" "create(\"users\")" "update(\"users\")" "delete(\"users\")"
appwrite databases update-collection --database-id $DatabaseId --collection-id "name_votes" --permissions "read(\"users\")" "create(\"users\")" "update(\"users\")" "delete(\"users\")"

Write-Host "-> class_students attributes"
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "class_students" --key "classId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "class_students" --key "publicToken" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "class_students" --key "studentId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "class_students" --key "name" --size 64 --required true
appwrite databases create-datetime-attribute --database-id $DatabaseId --collection-id "class_students" --key "updatedAt" --required true

Write-Host "-> class_students indexes"
appwrite databases create-index --database-id $DatabaseId --collection-id "class_students" --key "byClass" --type "key" --attributes "classId"
appwrite databases create-index --database-id $DatabaseId --collection-id "class_students" --key "byClassStudent" --type "key" --attributes "classId" "studentId"

Write-Host "-> name_votes attributes"
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "name_votes" --key "classId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "name_votes" --key "tabId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "name_votes" --key "publicToken" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "name_votes" --key "voterStudentId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "name_votes" --key "choice1StudentId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "name_votes" --key "choice2StudentId" --size 64 --required true
appwrite databases create-string-attribute --database-id $DatabaseId --collection-id "name_votes" --key "choice3StudentId" --size 64 --required true
appwrite databases create-datetime-attribute --database-id $DatabaseId --collection-id "name_votes" --key "updatedAt" --required true

Write-Host "-> name_votes indexes"
appwrite databases create-index --database-id $DatabaseId --collection-id "name_votes" --key "byTab" --type "key" --attributes "tabId"
appwrite databases create-index --database-id $DatabaseId --collection-id "name_votes" --key "byTabVoter" --type "key" --attributes "tabId" "voterStudentId"

Write-Host ""
Write-Host "Done. In Appwrite Console, wait until new attributes show status 'available' (not building)."
Write-Host "Then deploy the 'classroom' Appwrite function."

