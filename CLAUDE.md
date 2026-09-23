# CLAUDE.md

Guidance for Claude Code when working in this repository. Read
[ARCHITECTURE.md](ARCHITECTURE.md) for how the system fits together and
[PRD.md](PRD.md) for what the product must do. [AGENTS.md](AGENTS.md) holds the
shared rules for every coding agent; everything there applies here too.

## Project in one paragraph

Popper is an offline-first "I went" logger. `frontend/` is a Flutter app that
writes every entry to a local Hive box first, then syncs to `backend/`, an
Express 5 + Mongoose API backed by MongoDB. Users are anonymous: a UUID device
ID sent as the `x-device-id` header (hashed server-side) is the only identity.

## Layout

```
frontend/   Flutter app (package `popper`) — run Flutter commands from here
  lib/config    AppConfig: persisted server target + backdate range
  lib/models    LogEntry (Hive typeId 0) + generated adapter
  lib/data      LocalDB (Hive wrapper), MockData seeder
  lib/services  ApiService, SyncService, ExportService
  lib/screens   HomeScreen, HistoryScreen, BackOfficeScreen
backend/    Node API — run npm commands from here
  server.js, connectDB.js, src/api.js, api.test.js
```

## Commands

Frontend (`cd frontend`):

```bash
flutter pub get
flutter analyze                 # must not add new issues
flutter test                    # widget test initialises Hive in a temp dir
flutter run                     # add -d chrome / -d windows / -d <device>
dart run build_runner build --delete-conflicting-outputs   # after editing LogEntry
dart run flutter_launcher_icons                              # after changing lib/assets/lol.png
```

Backend (`cd backend`):

```bash
npm install
cp .env.example .env            # set MONGO_URI (and PORT, default 3081)
npm start                       # node server.js
npm test                        # jest — hits the real MONGO_URI in .env
```

`flutter analyze` currently reports 3 pre-existing issues (unused `_isSyncing`
in home_screen, an unnecessary cast in api_service, a missing brace in
history_screen). Don't count them as yours; don't add more.

## Rules that matter here

1. **Don't change behaviour unasked.** Default settings must reproduce the
   shipped app exactly. New behaviour goes behind `AppConfig` flags that
   default to the old behaviour.
2. **Local first.** Any new write path saves to `LocalDB` before touching the
   network, and marks `isSynced` only after a 2xx.
3. **Hive schema is append-only.** Never renumber `@HiveField`s or change
   `typeId: 0`. Add new fields with new indices and a default.
4. **Base URL comes from `AppConfig.baseUrl`.** Never hard-code a server URL
   in a service or screen; add a `ServerTarget` instead.
5. **The Back Office stays hidden.** No visible button, menu item, or text
   containing "developer" / "debug" / "dev settings". Entry is 7 taps on the
   Home header date within 3 s (`_onHeaderTap` in `home_screen.dart`).
6. **Match the design system.** Reuse the palette constants
   (Linen `#EEE8DC`, Walnut `#1C1510`, Dust `#8C7B68`, Rule `#C9BFA8`,
   Terracotta `#B85C38`), `IBMPlexMono` uppercase labels with letter-spacing,
   `PlayfairDisplay` italic for display text, square corners, 1 px rules.
   Snackbars are floating, square, Walnut with a coloured dot.
7. **Never commit secrets.** `backend/.env` is ignored; only `.env.example`
   is tracked. Don't print `MONGO_URI`.
8. **Backend is imported by tests.** Keep `src/api.js` exporting the app
   without calling `listen()`.

## Common tasks

- **Add an API call:** method in `ApiService` using `baseUrl` and the
  `x-device-id` header → throw on non-2xx if the caller must know → route in
  `backend/src/api.js` behind `requireDevice` → update the route table in
  ARCHITECTURE.md.
- **Add a Back Office option:** persist it in `AppConfig` (new `_k` key,
  getter, setter, include in `reset()`), render with `_toggleRow` /
  `_actionRow` in `back_office_screen.dart`, and read it where needed.
- **Add a screen:** file in `lib/screens/`, named route in `main.dart`,
  pass `deviceId` through the constructor.
- **Point the app at a local backend:** start the backend, open the Back
  Office, pick **Localhost** (web/desktop/iOS sim) or **Android emulator**,
  then **Test connection**. Physical device → **Custom** with the machine's
  LAN IP, debug build.

## Verification before you say "done"

- `flutter analyze` shows no new issues and `flutter test` passes.
- For backend changes, `node -e "require('./src/api')"` loads cleanly; run
  `npm test` only when a disposable `MONGO_URI` is configured.
- Docs updated when routes, settings, or the data model change.

## Git

Single repo at the root; `master` is the main branch. Commit messages are
short imperative summaries (e.g. `Add CSV export to back office`). Don't
commit `frontend/build/`, `.dart_tool/`, `backend/node_modules/` or `.env`.
