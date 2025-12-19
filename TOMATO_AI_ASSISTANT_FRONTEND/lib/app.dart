// Main app configuration file
class AppConfig {
  static const String appName = 'Tomato AI Assistant';
  static const String version = '1.0.0';
  
  // API endpoints (replace with your actual endpoints)
  static const String diseaseDetectionApi = 'https://your-api.com/detect';
  static const String soilDataApi = 'https://your-api.com/soil';
  static const String dataFusionApi = 'https://your-api.com/fusion';
}

class AppRoutes {
  static const String home = '/';
  static const String diseaseDetection = '/disease-detection';
  static const String soilAnalysis = '/soil-analysis';
  static const String results = '/results';
  static const String settings = '/settings';
}