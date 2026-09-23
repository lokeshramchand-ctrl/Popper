const express = require('express');
const mongoose = require('mongoose');
const crypto = require('crypto');
const cors = require('cors');

const app = express();

const corsOptions = {
  origin: '*',
  methods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'x-device-id'],
};

app.use(cors(corsOptions));
app.options('/{*path}', cors(corsOptions));

app.use(express.json());


app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

// ===== MODEL =====
const logSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  userId: { type: String, required: true, index: true },
  timestamp: { type: Date, required: true },
  note: { type: String, default: '' },
  updatedAt: { type: Date, default: Date.now }
});

const Log = mongoose.model('Log', logSchema);

// ===== UTIL =====
function getUserId(deviceId) {
  return crypto.createHash('sha256').update(deviceId).digest('hex');
}

function getDayRange(dateStr) {
  const date = new Date(dateStr);
  const start = new Date(date.setHours(0, 0, 0, 0));
  const end = new Date(date.setHours(23, 59, 59, 999));
  return { start, end };
}

// ===== MIDDLEWARE =====
function requireDevice(req, res, next) {
  const deviceId = req.headers['x-device-id'];

  if (!deviceId) {
    return res.status(400).json({ error: 'Missing x-device-id' });
  }

  req.userId = getUserId(deviceId);
  next();
}

// ===== ROUTES =====

app.get('/', (req, res) => {
  res.send('API is running');
});
app.get('/logs/recent', requireDevice, async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 10000;

    const logs = await Log.find({ userId: req.userId })
      .sort({ timestamp: -1 })
      .limit(limit);

    res.json({ data: logs });

  } catch (err) {
    console.error('❌ /logs/recent:', err.message);
    res.status(500).json({ error: 'Internal error' });
  }
});
app.delete('/log/:id', requireDevice, async (req, res) => {
  try {
    const result = await Log.deleteOne({
      id: req.params.id,
      userId: req.userId
    });

    res.json({
      success: true,
      deleted: result.deletedCount
    });

  } catch (err) {
    console.error('❌ DELETE /log:', err.message);
    res.status(500).json({ error: 'Internal error' });
  }
});
// Create
app.post('/log', requireDevice, async (req, res) => {
  try {
    const { id, timestamp, note } = req.body;

    if (!id) return res.status(400).json({ error: 'id required' });

    const log = await Log.findOneAndUpdate(
      { id },
      {
        userId: req.userId,
        timestamp: timestamp ? new Date(timestamp) : new Date(),
        note: note || '',
        updatedAt: new Date()
      },
      { upsert: true, new: true }
    );

    res.json({ success: true, data: log });

  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Day logs
app.get('/logs/day', requireDevice, async (req, res) => {
  try {
    const { date } = req.query;
    const { start, end } = getDayRange(date);

    const logs = await Log.find({
      userId: req.userId,
      timestamp: { $gte: start, $lte: end }
    });

    res.json({ data: logs });

  } catch (err) {
    res.status(500).json({ error: 'Internal error' });
  }
});

// Latest
app.get('/logs/latest', requireDevice, async (req, res) => {
  const log = await Log.findOne({ userId: req.userId }).sort({ timestamp: -1 });
  res.json({ data: log });
});

// Status
app.get('/status/today', requireDevice, async (req, res) => {
  const today = new Date().toISOString().slice(0, 10);
  const { start, end } = getDayRange(today);

  const exists = await Log.exists({
    userId: req.userId,
    timestamp: { $gte: start, $lte: end }
  });

  res.json({ done: !!exists });
});

module.exports = app; 
