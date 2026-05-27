# Teachers Help (Flutter Web)

Teacher admin creates **tabs** (categories) with **cards** (one image + one audio). Students view **one image per screen** and use left/right arrows to navigate.

## Configure

Run the app with `--dart-define` values:

```bash
flutter run -d chrome --dart-define=APPWRITE_ENDPOINT="https://cloud.appwrite.io/v1" --dart-define=APPWRITE_PROJECT_ID="YOUR_PROJECT_ID"
```

Optional overrides:

- `APPWRITE_DATABASE_ID` (default `teachers_help`)
- `APPWRITE_CLASSES_COLLECTION_ID` (default `classes`)
- `APPWRITE_TABS_COLLECTION_ID` (default `tabs`)
- `APPWRITE_CARDS_COLLECTION_ID` (default `cards`)
- `APPWRITE_RANKING_SUBMISSIONS_COLLECTION_ID` (default `ranking_submissions`)
- `APPWRITE_DRIVE_CONNECTIONS_COLLECTION_ID` (default `drive_connections`)
- `APPWRITE_DRIVE_FUNCTION_ID` (default `drive`)
- `APPWRITE_RANKING_FUNCTION_ID` (default `ranking`)

## Appwrite schema

If you use the Appwrite CLI, you can create the database/collections/indexes with:

```powershell
.\scripts\appwrite_setup.ps1 -ProjectId "<YOUR_PROJECT_ID>" -ApiKey "<YOUR_API_KEY>"
```

## Dev

```bash
cd teachers_help
flutter pub get
flutter run -d chrome
```

### PowerShell shortcuts

```powershell
.\scripts\run_web.ps1 -ProjectId "<YOUR_PROJECT_ID>"
.\scripts\build_web.ps1 -ProjectId "<YOUR_PROJECT_ID>"
```

## GitHub Pages

Publieke site (na elke push naar `main`): [https://boonendenni.github.io/teachers-help/](https://boonendenni.github.io/teachers-help/)

Bronrepo: [https://github.com/BoonenDenni/teachers-help](https://github.com/BoonenDenni/teachers-help)

De workflow [.github/workflows/deploy-pages.yml](.github/workflows/deploy-pages.yml) bouwt Flutter Web en zet `404.html` gelijk aan `index.html` zodat routes na een refresh werken.

**Repository secrets** (Settings → Secrets and variables → Actions): zet minstens `APPWRITE_ENDPOINT` en `APPWRITE_PROJECT_ID`. Voor Google Drive-picker in de webapp: `GOOGLE_API_KEY`. Zonder secrets valt de build terug op de defaults in `lib/config/app_config.dart` (niet aanbevolen voor productie).

**Appwrite:** voeg in het project onder **Platforms** je exacte Pages-URL toe (bijv. `https://boonendenni.github.io` en het pad `/teachers-help/` indien gevraagd), zodat webclients requests mogen doen.

**Google Cloud (Drive API key):** beperk de key tot HTTP-verwijzers die je site matchen, bijv. `https://boonendenni.github.io/teachers-help/*` en `http://localhost:*` voor lokaal testen.

## Eerste push met GitHub CLI

Als `git push` weigert vanwege workflow-bestanden, breid je token uit: `gh auth refresh -h github.com -s workflow`, daarna opnieuw pushen.

# teachers_help

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
