# Popper

One tap to log it. An offline-first Flutter app with a small Node/MongoDB
sync backend.

```
frontend/   Flutter app
backend/    Express + MongoDB API
```

## Quick start

```bash
# backend
cd backend
npm install
cp .env.example .env      # set MONGO_URI
npm start                 # http://localhost:3081

# app
cd frontend
flutter pub get
flutter run
```

The app talks to the deployed server by default. To use a local backend, open
the hidden Back Office (tap the date on the home screen 7 times quickly) and
choose **Localhost** or **Android emulator**.

## Docs

- [PRD.md](PRD.md) — what the product does and why
- [ARCHITECTURE.md](ARCHITECTURE.md) — how it is built
- [AGENTS.md](AGENTS.md) — rules for AI coding agents
- [CLAUDE.md](CLAUDE.md) — Claude Code guidance
