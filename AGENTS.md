# AGENTS.md

Instructions for any AI coding agent (Claude Code, Codex, Cursor, Copilot,
etc.) working on Popper. Claude-specific notes live in [CLAUDE.md](CLAUDE.md);
system design in [ARCHITECTURE.md](ARCHITECTURE.md); requirements in
[PRD.md](PRD.md).

## Setup

| Part      | Stack                                          | Directory   |
|-----------|------------------------------------------------|-------------|
| App       | Flutter (Dart SDK ^3.11.5), Hive, http         | `frontend/` |
| API       | Node.js, Express 5, Mongoose 9, Jest/supertest | `backend/`  |
| Database  | MongoDB                                        | via `MONGO_URI` |

```bash
# app
cd frontend && flutter pub get && flutter run

# api
cd backend && npm install && cp .env.example .env && npm start   # :3081
```

## Test and lint

```bash
cd frontend && flutter analyze && flutter test
cd backend  && npm test        # needs a reachable MONGO_URI; writes + deletes one test record
```

Baseline: `flutter analyze` has 3 pre-existing issues. A change is acceptable
only if it adds none and `flutter test` passes.

## Hard rules

1. Preserve existing behaviour unless the task explicitly changes it. Put new
   behaviour behind an `AppConfig` setting whose default is the old behaviour.
2. Write locally before networking. `LocalDB.save()` first; set
   `isSynced = true` only after a 2xx response.
3. Hive model is append-only: keep `typeId: 0` and field indices 0–2; regenerate
   `log_entry.g.dart` with build_runner after edits and commit the result.
4. All HTTP goes through `ApiService`, which reads `AppConfig.baseUrl`. No
   hard-coded hosts elsewhere.
5. Every authenticated request sends `x-device-id`. The backend must keep
   hashing it (`sha256`) before storage.
6. The Back Office must remain hidden and unlabelled as a developer tool.
   Don't add visible entry points.
7. Follow the Apothecary Logbook design (palette, IBM Plex Mono labels,
   Playfair Display italic headings, square corners, 1 px rules).
8. Never commit `.env`, credentials, `node_modules/`, `build/`, `.dart_tool/`
   or archives (`*.zip`).
9. Keep `backend/src/api.js` exporting the Express app without `listen()`.
10. Update ARCHITECTURE.md / PRD.md in the same change when routes, settings,
    data model, or user-visible behaviour change.

## Code conventions

**Dart**
- Files `snake_case.dart`; one screen per file under `lib/screens/`.
- Services are plain classes; `LocalDB`, `AppConfig`, `ExportService`,
  `MockData` are static utility classes.
- Section comments use the existing `// ── Name ───` banner style.
- Use relative imports within `lib/` (as the existing code does).
- Guard `setState` / `context` after `await` with `if (!mounted) return;`.
- Log with `debugPrint('[Area] message')`.

**JavaScript**
- CommonJS (`require`), 2-space indent, async/await with `try/catch` returning
  `500 { error: 'Internal error' }`.
- New per-user routes use the `requireDevice` middleware and filter by
  `req.userId`.

## Where things are

| Need to…                               | Look at                                         |
|----------------------------------------|-------------------------------------------------|
| Change what "I WENT" does              | `frontend/lib/screens/home_screen.dart` `addLog` |
| Change sync rules                      | `frontend/lib/services/sync_service.dart`       |
| Change backdate limits                 | `history_screen.dart` `_showBackdateSheet` + `AppConfig.openDateRange` |
| Add a server option                    | `frontend/lib/config/app_config.dart` `ServerTarget` |
| Add export fields / formats            | `frontend/lib/services/export_service.dart`     |
| Add a hidden setting                   | `frontend/lib/screens/back_office_screen.dart`  |
| Add / change an endpoint               | `backend/src/api.js`                            |
| Change DB connection                   | `backend/connectDB.js`                          |

## Hidden Back Office quick reference

Open: Home → tap the date in the header **7 times within 3 seconds**.

| Section | Option                | Effect                                                   |
|---------|-----------------------|----------------------------------------------------------|
| Server  | Deployed              | `https://lt9e0fj1favccw8wxgggl2d2.deploy.splsystems.in`  |
|         | Localhost             | `http://localhost:3081`                                  |
|         | Android emulator      | `http://10.0.2.2:3081`                                   |
|         | Custom                | any URL, saved with **USE**                              |
|         | Test connection       | `GET /` with round-trip time                             |
| Dates   | Open date range       | backdate picker allows today and dates back to 2000      |
| Data    | Export JSON / CSV     | clipboard + `popper_export_<time>.<ext>` in app documents |
|         | Push pending          | `SyncService.sync`                                       |
|         | Pull from server      | `SyncService.restoreFromServer`                          |
|         | Seed sample data      | `MockData.seed(clearFirst: false)`                       |
|         | Wipe local data       | clears Hive box (server untouched)                       |
| Device  | Device ID             | tap to copy                                              |

Cleartext `http://` backends work in Android debug/profile builds and on iOS
local networks; Android release builds require HTTPS.

## Pull requests

- One logical change per PR; describe user-visible effects and how you
  verified them (analyze/test output, device or platform used).
- Screenshots for UI changes.
- Call out any change to the Hive model, API contract, or stored settings keys.
