# Local Flutter web with CanvasKit bundled (avoids blank screen when gstatic CDN is blocked/slow).
# Usage: .\scripts\run_web.ps1 --dart-define=GOOGLE_API_KEY="your-key"
Set-Location (Join-Path $PSScriptRoot "..")
flutter run -d edge --no-web-resources-cdn @args