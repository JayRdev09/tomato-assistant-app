const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 8000;

// Security middleware
app.use(helmet());
app.use(compression());

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use(limiter);

// CORS configuration - Updated for Flutter Web
app.use(cors({
  origin: function (origin, callback) {
    // Allow requests with no origin (like mobile apps, Postman, etc.)
    if (!origin) return callback(null, true);
    
    // List of allowed origins
    const allowedOrigins = [
      'http://localhost:51349',
      'http://localhost:62920',
      'http://localhost:62921', 
      'http://localhost:62922',
      'http://localhost:3000',
      'http://localhost:53591',
      'http://localhost:60000',
      'http://localhost:60001',
      'http://localhost:60002',
      'http://192.168.1.195:3000',
      'http://192.168.1.195:8000',
      'http://127.0.0.1:3000',
      'http://127.0.0.1:8000',
      'http://localhost:8000',
      // Flutter web development server ports
      'http://localhost:5000',
      'http://localhost:5001',
      'http://localhost:8080',
      'http://localhost:8081',
      // Supabase Auth redirect origins
      process.env.SUPABASE_REDIRECT_URL || 'http://localhost:3000',
      // Allow all localhost ports for Flutter web development
      /^http:\/\/localhost:\d+$/,
      /^http:\/\/192\.168\.1\.\d+:\d+$/,
      /^http:\/\/127\.0\.0\.1:\d+$/
    ];
    
    if (allowedOrigins.some(allowed => {
      if (typeof allowed === 'string') {
        return origin === allowed;
      } else if (allowed instanceof RegExp) {
        return allowed.test(origin);
      }
      return false;
    })) {
      callback(null, true);
    } else {
      console.log('🚫 CORS blocked origin:', origin);
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
  allowedHeaders: [
    'Content-Type', 
    'Authorization', 
    'Accept', 
    'Origin', 
    'X-Requested-With',
    'X-Auth-Token',
    'X-CSRF-Token',
    'apikey',
    'Authorization'
  ],
  exposedHeaders: [
    'Content-Range',
    'X-Content-Range',
    'Link'
  ],
  maxAge: 86400
}));

// Handle preflight requests
app.options('*', cors());

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Import routes
const healthRoutes = require('./routes/health');
const soilRoutes = require('./routes/soil');
const analysisRoutes = require('./routes/analysis');
const imageRoutes = require('./routes/images');
const authRoutes = require('./routes/auth');

// Use routes
app.use('/api/health', healthRoutes);
app.use('/api/soil', soilRoutes);
app.use('/api/analysis', analysisRoutes);
app.use('/api/images', imageRoutes);
app.use('/api/auth', authRoutes);

// Health check endpoint (root)
app.get('/', (req, res) => {
  res.json({
    message: 'Tomato AI Backend API with Supabase',
    version: '2.0.0',
    storage: 'Supabase Storage + Database',
    auth: 'Supabase Auth',
    endpoints: {
      health: '/api/health',
      soil: '/api/soil',
      analysis: '/api/analysis',
      images: '/api/images',
      auth: '/api/auth'
    },
    timestamp: new Date().toISOString()
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: `API endpoint not found: ${req.method} ${req.path}`,
    available_endpoints: [
      'GET  /api/health',
      'GET  /api/soil/status',
      'POST /api/soil/store',
      'GET  /api/analysis/data-status',
      'POST /api/analysis/integrated',
      'GET  /api/analysis/history',
      'POST /api/images/upload',
      'GET  /api/images',
      'POST /api/images/transform',
      'GET  /api/images/usage',
      'POST /api/auth/signup',
      'POST /api/auth/login',
      'POST /api/auth/verify-token',
      'GET  /api/auth/profile',
      'PUT  /api/auth/profile',
      'GET  /api/auth/status',
      'DELETE /api/auth/account'
    ]
  });
});

// Error handling middleware
app.use((error, req, res, next) => {
  console.error('Error:', error);
  res.status(500).json({
    success: false,
    message: 'Internal server error'
  });
});

// Start server on all network interfaces
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Tomato AI Backend with Supabase running on port ${PORT}`);
  console.log(`📍 Local: http://localhost:${PORT}`);
  console.log(`📍 Network: http:// 192.168.1.14:${PORT}`);
  console.log(`📍 Health: http://localhost:${PORT}/api/health`);
  console.log(`📍 Auth: http://localhost:${PORT}/api/auth`);
});