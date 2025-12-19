# Tomato Assistant App

Full-stack application with Node.js backend and Flutter frontend.

## 📁 Project Structure
- `backend-node/` - Express.js REST API backend
- `tomatoalassistantwithauth/` - Flutter mobile application frontend

## 👥 Developers
- **JOJENE IAN BRYLLE LOCSIN**
- **GODIE S. BANGHAL JR**
- **JAMES BRYAN B. HUSSIN**

## 🚀 Setup Instructions

### Backend Setup (Node.js/Express)
```bash
# Navigate to backend directory
cd backend-node

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
cd tomatoalassistantwithauth

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
Create `.env` file in `backend-node/` with the following structure:
```
PORT=3000
DATABASE_URL=your_mongodb_url_here
JWT_SECRET=your_secret_key_here
NODE_ENV=development
```

## 🔧 Prerequisites
### For Backend:
- Node.js (v16 or higher)
- npm or yarn
- MongoDB (local or cloud)

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
backend-node/
├── src/
│   ├── controllers/  # Request handlers
│   ├── models/       # Database models
│   ├── routes/       # API routes
│   ├── middleware/   # Auth & validation
│   └── config/       # Configuration files
└── package.json

tomatoalassistantwithauth/
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

## 📞 Support
For technical issues, please contact the development team.

---

**Developed with ❤️ by Team Tomato Assistant**