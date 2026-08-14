require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
  console.error('JWT_SECRET is not set. Refusing to start with an insecure default.');
  process.exit(1);
}

// Build the connection string from the ConfigMap/Secret parts the deployment
// injects (MONGODB_HOST/PORT/DATABASE from app2-config, MONGODB_USERNAME/PASSWORD
// from app2-secrets). A full MONGODB_URI still takes precedence.
const mongoHost = process.env.MONGODB_HOST || 'mongodb';
const mongoPort = process.env.MONGODB_PORT || '27017';
const mongoDatabase = process.env.MONGODB_DATABASE || 'app2';
const mongoUser = process.env.MONGODB_USERNAME;
const mongoPass = process.env.MONGODB_PASSWORD;
const authPart = (mongoUser && mongoPass)
  ? `${encodeURIComponent(mongoUser)}:${encodeURIComponent(mongoPass)}@`
  : '';
const authSource = (mongoUser && mongoPass) ? '?authSource=admin' : '';
const MONGODB_URI = process.env.MONGODB_URI ||
  `mongodb://${authPart}${mongoHost}:${mongoPort}/${mongoDatabase}${authSource}`;

mongoose.connect(MONGODB_URI)
  .then(() => console.log('Connected to MongoDB'))
  .catch(err => {
    console.error('MongoDB connection error:', err.message);
    if (process.env.NODE_ENV !== 'test') process.exit(1);
  });

const itemSchema = new mongoose.Schema({
  name: { type: String, required: true },
  description: String,
  quantity: { type: Number, default: 0 },
  owner: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true }
}, { timestamps: true });

const userSchema = new mongoose.Schema({
  email: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  createdAt: { type: Date, default: Date.now }
});

userSchema.pre('save', async function(next) {
  if (!this.isModified('password')) return next();
  this.password = await bcrypt.hash(this.password, 10);
  next();
});

const Item = mongoose.model('Item', itemSchema);
const User = mongoose.model('User', userSchema);

// Mass-assignment guard: only these fields are ever copied from the request body.
const ITEM_FIELDS = ['name', 'description', 'quantity'];
function pickItemFields(data) {
  const out = {};
  for (const f of ITEM_FIELDS) {
    if (data[f] !== undefined) out[f] = data[f];
  }
  return out;
}

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'Access token required' });

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ error: 'Invalid token' });
    req.user = user;
    next();
  });
};

app.get('/', (req, res) => {
  res.json({
    name: 'app2-node (Node.js + MongoDB)',
    status: 'healthy',
    database: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
    endpoints: ['/health', '/auth/register', '/auth/login', '/items']
  });
});

app.get('/health', (req, res) => {
  const connected = mongoose.connection.readyState === 1;
  if (!connected) {
    res.status(503).json({ status: 'unhealthy', database: 'disconnected' });
  } else {
    res.json({ status: 'healthy', database: 'connected' });
  }
});

app.post('/auth/register', async (req, res) => {
  try {
    const { email, password } = req.body;
    const existing = await User.findOne({ email });
    if (existing) return res.status(400).json({ error: 'Email already registered' });
    
    const user = new User({ email, password });
    await user.save();
    
    const token = jwt.sign({ userId: user._id, email: user.email }, JWT_SECRET, { expiresIn: '24h' });
    res.status(201).json({ token, user: { id: user._id, email: user.email } });
  } catch (err) {
    res.status(500).json({ error: 'Registration failed' });
  }
});

app.post('/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const user = await User.findOne({ email });
    if (!user) return res.status(401).json({ error: 'Invalid credentials' });
    
    const valid = await bcrypt.compare(password, user.password);
    if (!valid) return res.status(401).json({ error: 'Invalid credentials' });
    
    const token = jwt.sign({ userId: user._id, email: user.email }, JWT_SECRET, { expiresIn: '24h' });
    res.json({ token, user: { id: user._id, email: user.email } });
  } catch (err) {
    res.status(500).json({ error: 'Login failed' });
  }
});

app.get('/items', authenticateToken, async (req, res) => {
  try {
    const items = await Item.find({ owner: req.user.userId }).sort({ createdAt: -1 });
    res.json(items);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch items' });
  }
});

app.post('/items', authenticateToken, async (req, res) => {
  try {
    const data = pickItemFields(req.body);
    if (Object.keys(data).length === 0) {
      return res.status(400).json({ error: 'No valid fields to create item' });
    }
    const item = new Item({ ...data, owner: req.user.userId });
    await item.save();
    res.status(201).json(item);
  } catch (err) {
    res.status(500).json({ error: 'Failed to create item' });
  }
});

app.get('/items/:id', authenticateToken, async (req, res) => {
  try {
    const item = await Item.findOne({ _id: req.params.id, owner: req.user.userId });
    if (!item) return res.status(404).json({ error: 'Item not found' });
    res.json(item);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch item' });
  }
});

app.put('/items/:id', authenticateToken, async (req, res) => {
  try {
    const data = pickItemFields(req.body);
    if (Object.keys(data).length === 0) {
      return res.status(400).json({ error: 'No valid fields to update' });
    }
    const item = await Item.findOneAndUpdate(
      { _id: req.params.id, owner: req.user.userId },
      data,
      { new: true, runValidators: true }
    );
    if (!item) return res.status(404).json({ error: 'Item not found' });
    res.json(item);
  } catch (err) {
    res.status(500).json({ error: 'Failed to update item' });
  }
});

app.delete('/items/:id', authenticateToken, async (req, res) => {
  try {
    const item = await Item.findOneAndDelete({ _id: req.params.id, owner: req.user.userId });
    if (!item) return res.status(404).json({ error: 'Item not found' });
    res.status(204).send();
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete item' });
  }
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

module.exports = app;