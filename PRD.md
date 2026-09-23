# Product Requirements — Popper

## 1. Summary

Popper is a single-purpose, privacy-light bowel-movement logger. The core
interaction is one button: **I WENT**. Everything else — history, backdating,
sync — exists to make that one tap trustworthy over time.

## 2. Problem

People who track bowel habits (for IBS, diet changes, medication, post-surgery
recovery or doctor visits) use generic notes apps or habit trackers. Those are
slow to open, need accounts, and don't answer the two questions that matter at
a glance: *"Have I gone today?"* and *"When was the last time?"*

## 3. Goals

| # | Goal                                                    | Measure                                  |
|---|---------------------------------------------------------|------------------------------------------|
| G1 | Log an event in one tap, under 2 seconds from launch   | No forms, no confirmation on the happy path |
| G2 | Work fully offline                                     | Every feature except sync/restore works with no network |
| G3 | Never lose an entry                                    | Entries persist locally before any network call; sync retries |
| G4 | No sign-up                                             | Anonymous device ID only                 |
| G5 | Calm, distinctive feel                                 | "Apothecary Logbook" visual language     |

### Non-goals

- Accounts, login, multi-device merge by identity.
- Medical interpretation, reminders, or notifications.
- Detailed attributes (Bristol scale, notes) — `note` exists server-side but is
  intentionally not exposed yet.

## 4. Users

- **Primary:** an individual tracking their own habits on one phone.
- **Secondary:** the developer/operator, who needs to point the app at local or
  staging servers, export data, and test backdated histories without shipping a
  separate build.

## 5. Functional requirements

### 5.1 Home

- FR-1 Show today's date in the header (`MON  23 SEP 2026`).
- FR-2 Hero status: **Not yet.** (no entry today), **Wented.** (one), or
  **Wented ×N** (N > 1), with a matching sub-label.
- FR-3 **I WENT** / **I WENT AGAIN** button is always enabled; each tap creates
  one entry with the current time. Taps are debounced only while a save is in
  flight.
- FR-4 Show **LAST RECORDED** time (`Today 7:42 AM` or `dd/mm h:mm AM`).
- FR-5 Link to History; refresh Home on return.
- FR-6 Haptic feedback and stamp animation on log.

### 5.2 History ("Log Register")

- FR-7 List all entries newest first, grouped by month with counts.
- FR-8 Each row shows day, weekday, time, **SYNCED/LOCAL** state, and a
  **BACKDATED** marker for entries before today.
- FR-9 Total record count in the header.
- FR-10 **ADD PAST ENTRY**: pick date and time; by default only dates before
  today are allowed (2020 onward).
- FR-11 Swipe left to delete with a confirmation sheet; synced entries are also
  deleted on the server; failure restores the entry locally.
- FR-12 **RESTORE** pulls server records missing locally.
- FR-13 **FORCE SYNC** pushes pending entries; shows **OFFLINE** when there is
  no connectivity. Auto-sync on open and on reconnect.
- FR-14 Empty state invites adding a past entry.

### 5.3 Sync & identity

- FR-15 A UUID device ID is created on first launch and persisted.
- FR-16 Entries are marked synced only after a 2xx from the server.
- FR-17 Restore never overwrites or removes local entries.

### 5.4 Back Office (hidden)

Accessible by tapping the Home header date 7 times within 3 seconds. Not
labelled "developer" anywhere in the UI.

- FR-18 Choose the backend: **Deployed**, **Localhost** (`localhost:3081`),
  **Android emulator** (`10.0.2.2:3081`) or **Custom** URL. Persist across
  launches. Apply without restart.
- FR-19 **Test connection** reports reachability and round-trip time.
- FR-20 **Open date range** toggle lets the backdate picker select today and
  any date back to 2000 (future times still rejected).
- FR-21 **Export** local data as JSON or CSV — to clipboard, and to a file in
  the app documents directory on mobile/desktop.
- FR-22 **Push pending**, **Pull from server**, **Seed sample data**, **Wipe
  local data** (confirmation required).
- FR-23 Show device ID (copyable) and local / pending counts.
- FR-24 **Reset settings** returns to shipped defaults.

With default settings the app behaves exactly as it did before the Back Office
existed.

### 5.5 Backend API

See the route table in [ARCHITECTURE.md](ARCHITECTURE.md#routes). Requirements:

- BR-1 Identify callers only by `x-device-id`, storing its SHA-256 hash.
- BR-2 `POST /log` is idempotent per `id` (upsert).
- BR-3 CORS must allow the Flutter web build.
- BR-4 `GET /` is an unauthenticated health check.

## 6. Non-functional requirements

- NFR-1 **Offline:** local writes never wait on the network.
- NFR-2 **Privacy:** no names, emails or raw device IDs on the server.
- NFR-3 **Platforms:** Android and iOS primary; web and desktop build.
- NFR-4 **Performance:** Home interactive immediately after Hive opens;
  history comfortable with thousands of entries (server returns up to 10 000).
- NFR-5 **Security:** release Android builds use HTTPS only; cleartext is
  enabled for debug/profile builds to support local backends.

## 7. Future ideas

- Include `userId` in the `POST /log` upsert filter.
- Notes / Bristol scale on entries (backend already has `note`).
- Streaks and weekly summaries.
- Share-sheet export (e.g. `share_plus`) instead of clipboard + file.
- Recovery code so a device ID can be moved to a new phone.
