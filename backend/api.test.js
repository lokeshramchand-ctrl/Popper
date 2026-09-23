const request = require('supertest');
const mongoose = require('mongoose');
const app = require('./src/api');
require('dotenv').config();

const DEVICE_ID = 'test-device-123';

beforeAll(async () => {
  await mongoose.connect(process.env.MONGO_URI);
});

afterAll(async () => {
  await mongoose.connection.close();
});

describe('API Tests', () => {

  it('GET / should work', async () => {
    const res = await request(app).get('/');
    expect(res.statusCode).toBe(200);
  });

  it('POST /log should create entry', async () => {
    const res = await request(app)
      .post('/log')
      .set('x-device-id', DEVICE_ID)
      .send({
        id: 'test-log-1',
        timestamp: new Date().toISOString()
      });

    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it('GET /status/today should return boolean', async () => {
    const res = await request(app)
      .get('/status/today')
      .set('x-device-id', DEVICE_ID);

    expect(res.statusCode).toBe(200);
    expect(typeof res.body.done).toBe('boolean');
  });

  it('GET /logs/latest should return latest log', async () => {
    const res = await request(app)
      .get('/logs/latest')
      .set('x-device-id', DEVICE_ID);

    expect(res.statusCode).toBe(200);
  });

  it('GET /logs/recent should return array', async () => {
    const res = await request(app)
      .get('/logs/recent')
      .set('x-device-id', DEVICE_ID);

    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  it('DELETE /log/:id should delete entry', async () => {
    const res = await request(app)
      .delete('/log/test-log-1')
      .set('x-device-id', DEVICE_ID);

    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

});