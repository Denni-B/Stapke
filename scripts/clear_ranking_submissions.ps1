param(
  [Parameter(Mandatory = $true)][string]$ProjectId,
  [Parameter(Mandatory = $true)][string]$ApiKey,
  [string]$Endpoint = "https://cloud.appwrite.io/v1",
  [string]$DatabaseId = "teachers_help",
  [int]$BatchSize = 100
)

$ErrorActionPreference = "Stop"

function Require-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $name. Install: npm i -g appwrite-cli"
  }
}

Require-Command "appwrite"

# Configure environment for the Appwrite CLI.
$env:APPWRITE_ENDPOINT = $Endpoint
$env:APPWRITE_PROJECT_ID = $ProjectId
$env:APPWRITE_API_KEY = $ApiKey

$CollectionId = "ranking_submissions"

Write-Host "Clearing all documents in '$CollectionId' (db=$DatabaseId project=$ProjectId endpoint=$Endpoint)..."

$deleted = 0
$offset = 0

while ($true) {
  $queries = @(
    "limit($BatchSize)"
    "offset($offset)"
  )

  $raw = appwrite databases list-documents --database-id $DatabaseId --collection-id $CollectionId --queries $queries
  $res = $raw | ConvertFrom-Json

  if ($null -eq $res.documents -or $res.documents.Count -eq 0) {
    break
  }

  foreach ($doc in $res.documents) {
    appwrite databases delete-document --database-id $DatabaseId --collection-id $CollectionId --document-id $doc.'$id' | Out-Null
    $deleted++
  }

  # If we didn't fill a full batch, we're done.
  if ($res.documents.Count -lt $BatchSize) {
    break
  }

  $offset += $BatchSize
}

Write-Host "Done. Deleted $deleted documents from '$CollectionId'."
