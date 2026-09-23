require('dotenv').config();

const connectDB = require('./connectDB');
const app = require('./src/api');

const PORT = process.env.PORT || 3081;

async function startServer() {
  try {
    await connectDB();

    app.listen(PORT, '0.0.0.0', () => {
      console.log(`Server running on port ${PORT}`);
    });

  } catch (err) {
    console.error('Startup error:', err);
    process.exit(1);
  }
}

startServer();