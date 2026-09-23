# Popper backend

Express 5 + Mongoose API for the Popper app. See
[../ARCHITECTURE.md](../ARCHITECTURE.md#backend) for routes and data model.

```bash
npm install
cp .env.example .env   # MONGO_URI, PORT (default 3081)
npm start
npm test               # runs against MONGO_URI
```
