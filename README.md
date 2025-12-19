# Tomato Assistant App

Full-stack application with Node.js backend and Flutter frontend.

## 📁 Project Structure
- `TOMATO_AI_ASSISTANT_BACKEND/` - Express.js REST API backend
- `TOMATO_AI_ASSISTANT_FRONTEND/` - Flutter mobile application frontend

## 👥 Developers
- **JOJENE IAN BRYLLE LOCSIN**
- **GODIE S. BANGHAL JR**
- **JAMES BRYAN B. HUSSIN**

## 🚀 Setup Instructions

### Backend Setup (Node.js/Express)
```bash
# Navigate to backend directory
cd TOMATO_AI_ASSISTANT_BACKEND

# Install dependencies
npm install

# Create .env file with your environment variables
# Copy from .env.example and update with your values
cp .env.example .env  # or create manually

# Start the server
npm start
# For development with auto-reload:
npm run dev
```

### Frontend Setup (Flutter)
```bash
# Navigate to Flutter directory
cd TOMATO_AI_ASSISTANT_FRONTEND

# Install dependencies
flutter pub get

# Run on connected device/emulator
flutter run
# For specific device:
flutter run -d <device_id>

# Build for production
flutter build apk
```

## 📋 Environment Variables
Create `.env` file in `TOMATO_AI_ASSISTANT_BACKEND/` with the following structure:
```
SUPABASE_URL=Supabase_URL
SUPABASE_SERVICE_KEY=Supabase_ServiceKey

PORT=8000
NODE_ENV=development
```

## 🔧 Prerequisites
### For Backend:
- Node.js (v16 or higher)
- npm or yarn
- SupaBase 

### For Frontend:
- Flutter SDK (latest stable version)
- Android Studio / Xcode (for mobile development)
- VS Code / Android Studio (IDE)

## 📱 Features
- User authentication and authorization
- Tomato farming assistant
- Real-time data tracking
- Cross-platform mobile application

## 🗂️ Project Structure Details
```
TOMATO_AI_ASSISTANT_BACKEND/
├── src/
│   ├── controllers/  # Request handlers
│   ├── models/       # Database models
│   ├── routes/       # API routes
│   ├── middleware/   # Auth & validation
│   └── config/       # Configuration files
└── package.json

TOMATO_AI_ASSISTANT_FRONTEND/
├── lib/
│   ├── screens/      # Flutter UI screens
│   ├── models/       # Data models
│   ├── services/     # API services
│   ├── widgets/      # Reusable widgets
│   └── utils/        # Utilities
└── pubspec.yaml
```

## 🐛 Troubleshooting
- **Flutter issues**: Run `flutter doctor` to diagnose problems
- **Node.js issues**: Ensure all dependencies are installed with `npm install`
- **Connection issues**: Verify backend is running on correct port and CORS is configured