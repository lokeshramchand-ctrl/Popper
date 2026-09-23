# Architecture

Popper is a small, offline-first logging app: one tap records "I went" with a
timestamp. The Flutter client stores every entry locally first and syncs to a
Node/Express + MongoDB backend in the background. There are no accounts: a
random device ID identifies a user.

```
┌──────────────────────── frontend/ (Flutter) ────────────────────────┐
│                                                                     │
│  screens/                                                           │
│   HomeScreen ──┐   HistoryScreen ──┐   BackOfficeScreen (hidden)    │
│                │                   │            │                   │
│                ▼                   ▼            ▼                   │
│  services/   SyncService ───────► ApiService ◄── AppConfig.baseUrl  │
│                │                   │  (http)       (config/)        │
│                ▼                   │                                │
│  data/       LocalDB (Hive box "logs")        ExportService         │
│                │                   │                                │
│  models/     LogEntry (HiveType 0) │                                │
└────────────────────────────────────┼────────────────────────────────┘
                                     │  HTTPS / HTTP
                                     │  header: x-device-id: <uuid>
┌────────────────────────── backend/ (Node) ──────────────────────────┐
│  server.js  → connectDB.js (mongoose.connect(MONGO_URI))            │
│             → src/api.js   (Express app, routes, Log model)         │
│                                   │                                 │
│                                   ▼                                 │
│                        MongoDB collection "logs"                    │
└─────────────────────────────────────────────────────────────────────┘
```

## Repository layout

```
Popper/
├── frontend/                 Flutter app (package name: popper)
│   ├── lib/
│   │   ├── main.dart         bootstrap: Hive, AppConfig, device id, routes
│   │   ├── config/
│   │   │   └── app_config.dart       persisted runtime settings (server, dates)
│   │   ├── models/
│   │   │   ├── log_entry.dart        Hive model
│   │   │   └── log_entry.g.dart      generated adapter (build_runner)
│   │   ├── data/
│   │   │   ├── local_db.dart         Hive box wrapper
│   │   │   └── mock_data.dart        sample-data seeder
│   │   ├── services/
│   │   │   ├── api_service.dart      HTTP client for the backend
│   │   │   ├── sync_service.dart     push unsynced / pull missing
│   │   │   └── export_service.dart   JSON / CSV export
│   │   ├── screens/
│   │   │   ├── home_screen.dart      "I WENT" button + today status
│   │   │   ├── history_screen.dart   log register, backdate, delete, sync
│   │   │   └── back_office_screen.dart  hidden configuration panel
│   │   └── assets/                   fonts + launcher icon (lol.png)
│   ├── test/widget_test.dart
│   ├── android/ ios/ web/ linux/ macos/ windows/   platform runners
│   └── pubspec.yaml
├── backend/                  Node.js API
│   ├── server.js             entry: loads .env, connects DB, listens
│   ├── connectDB.js          mongoose connection
│   ├── src/api.js            Express app (exported for supertest)
│   ├── api.test.js           Jest + supertest integration tests
│   ├── .env.example          MONGO_URI, PORT
│   └── package.json
├── ARCHITECTURE.md  PRD.md  CLAUDE.md  AGENTS.md  README.md
```

## Frontend

### Startup (`main.dart`)

1. `LocalDB.init()` – `Hive.initFlutter()`, registers `LogEntryAdapter`, opens
   box `logs`.
2. `AppConfig.init()` – loads server target / custom URL / date-range flag
   from SharedPreferences.
3. Reads `device_id` from SharedPreferences, generating a UUID v4 on first
   launch. This ID is passed to every screen and becomes the `x-device-id`
   header.
4. `MaterialApp` with named routes:

| Route          | Screen             | How it is reached                        |
|----------------|--------------------|------------------------------------------|
| `/`            | `HomeScreen`       | launch                                   |
| `/history`     | `HistoryScreen`    | "VIEW HISTORY" link on Home              |
| `/back-office` | `BackOfficeScreen` | tap the header date on Home 7× within 3 s |

### Data model

`LogEntry` (`models/log_entry.dart`, Hive `typeId: 0`):

| Field       | Hive index | Type       | Notes                                   |
|-------------|-----------:|------------|-----------------------------------------|
| `id`        | 0          | `String`   | UUID v4, also the Hive key              |
| `timestamp` | 1          | `DateTime` | local time when logged / backdated      |
| `isSynced`  | 2          | `bool`     | true once the server returned 2xx       |

Never renumber these fields or reuse `typeId: 0`; existing installs would fail
to read their box. After changing the model run
`dart run build_runner build --delete-conflicting-outputs` to regenerate
`log_entry.g.dart`.

### Offline-first write path

```
tap "I WENT"
  → LogEntry(id: uuid, timestamp: now, isSynced: false)
  → LocalDB.save()                         (UI updates immediately)
  → SyncService.sync(deviceId)
       for each unsynced entry:
         ApiService.createLog()  → POST /log
         2xx  → isSynced = true, LocalDB.update()
         else → leave for next attempt (exception caught + logged)
```

Sync is triggered:

- when `HomeScreen` loads and after every log,
- when `HistoryScreen` opens and there are unsynced entries and the device is online,
- when connectivity comes back (`connectivity_plus` stream on History),
- manually via **FORCE SYNC** on History or **PUSH PENDING** in the Back Office.

### Restore path

`SyncService.restoreFromServer()` → `GET /logs/recent` → inserts every remote
entry whose `id` is not in the local box, marked `isSynced: true`. It never
overwrites or deletes local data.

### Delete path

History swipe-left → confirm sheet → removed from Hive → if it was synced,
`DELETE /log/:id`. If the remote delete fails the entry is put back locally and
the user is told. 404 counts as success (already gone).

### Backdating

History → **ADD PAST ENTRY** opens a sheet with date + time pickers. Entries
are saved with `isSynced: false` and go through the normal sync path.

| `AppConfig.openDateRange` | first date | last date | validation                 |
|---------------------------|------------|-----------|----------------------------|
| `false` (default)         | 2020-01-01 | yesterday | must be before today 00:00 |
| `true`                    | 2000-01-01 | today     | must not be in the future  |

### Runtime configuration (`config/app_config.dart`)

Static class persisted in SharedPreferences (`cfg_server_target`,
`cfg_custom_url`, `cfg_open_date_range`). `ApiService.baseUrl` is a getter over
`AppConfig.baseUrl`, so switching servers takes effect on the next request with
no restart.

| `ServerTarget` | URL                                                      |
|----------------|----------------------------------------------------------|
| `deployed`     | `https://lt9e0fj1favccw8wxgggl2d2.deploy.splsystems.in`  |
| `localhost`    | `http://localhost:3081` (web, desktop, iOS simulator)    |
| `emulator`     | `http://10.0.2.2:3081` (Android emulator → host machine) |
| `custom`       | any URL entered in the Back Office (e.g. a LAN IP)       |

Cleartext `http://` is allowed in Android **debug/profile** builds only
(`android/app/src/{debug,profile}/AndroidManifest.xml`) and for local networks
on iOS (`NSAllowsLocalNetworking`). Release Android builds need HTTPS.

### Back Office (hidden panel)

Intentionally has no visible entry point or "developer" label. Features:

- **Server** – pick deployed / localhost / emulator / custom; test connection
  (`GET /`, shows round-trip ms).
- **Dates** – toggle the open backdate range (table above).
- **Data** – export JSON or CSV (copied to clipboard and written to the app
  documents directory via `path_provider`; clipboard only on web), push
  pending, pull from server, seed sample data (`MockData.seed(clearFirst: false)`),
  wipe local data (confirmation required; server untouched).
- **Device** – device ID (tap to copy), local and pending counts.
- **Reset settings** – restores all `AppConfig` defaults.

### Design system — "Apothecary Logbook"

Each screen redeclares the palette as `static const` colours:

| Token      | Hex       | Use                         |
|------------|-----------|-----------------------------|
| Linen      | `#EEE8DC` | background                  |
| Walnut     | `#1C1510` | primary ink, buttons        |
| Dust       | `#8C7B68` | secondary text              |
| Rule       | `#C9BFA8` | 1 px dividers               |
| Terracotta | `#B85C38` | accent: logged / synced     |

Fonts (bundled in `lib/assets/fonts`): **PlayfairDisplay** italic for display
words, **IBMPlexMono** for all labels, uppercase with wide letter-spacing.
Square corners everywhere, no elevation, 1 px rules.

## Backend

Express 5 app in `backend/src/api.js`, exported without `listen()` so tests can
import it. `server.js` loads `.env`, connects to Mongo, then listens on
`0.0.0.0:$PORT` (default **3081**).

### Identity

Every route except `GET /` requires `x-device-id`. The server stores
`userId = sha256(deviceId)`, so raw device IDs are never persisted. Missing
header → `400 { error: 'Missing x-device-id' }`.

### Model (`Log`, collection `logs`)

| Field       | Type   | Notes                        |
|-------------|--------|------------------------------|
| `id`        | String | required, unique (client UUID) |
| `userId`    | String | required, indexed            |
| `timestamp` | Date   | required                     |
| `note`      | String | default `''` (unused by app) |
| `updatedAt` | Date   | set on every upsert          |

### Routes

| Method | Path             | Body / query                    | Response                         |
|--------|------------------|---------------------------------|----------------------------------|
| GET    | `/`              | –                               | `API is running` (health check)  |
| POST   | `/log`           | `{ id, timestamp?, note? }`     | `{ success, data }` – upsert by `id` |
| DELETE | `/log/:id`       | –                               | `{ success, deleted }`           |
| GET    | `/logs/recent`   | `?limit` (default 10000)        | `{ data: Log[] }` newest first   |
| GET    | `/logs/day`      | `?date=YYYY-MM-DD`              | `{ data: Log[] }`                |
| GET    | `/logs/latest`   | –                               | `{ data: Log \| null }`          |
| GET    | `/status/today`  | –                               | `{ done: boolean }`              |

The Flutter app currently uses `/`, `POST /log`, `DELETE /log/:id` and
`/logs/recent`. `getTodayStatus`/`getLatest` exist in `ApiService` but the UI
derives "today" from the local box.

CORS: `origin: '*'`, methods GET/POST/DELETE/OPTIONS, headers
`Content-Type, x-device-id` (needed for Flutter web).

### Known quirks (documented, not yet changed)

- `POST /log` upserts on `{ id }` alone, not `{ id, userId }`. UUID collisions
  make this practically safe, but the filter should include `userId`.
- `getDayRange` uses the server's local timezone while `/status/today` derives
  the date from UTC; results can differ near midnight for non-UTC servers.
- `/logs/latest` and `/status/today` have no `try/catch` (Express 5 still
  forwards rejected promises to the default error handler).
- `api.test.js` runs against the real `MONGO_URI`; it creates and deletes a
  `test-log-1` record for device `test-device-123`.
