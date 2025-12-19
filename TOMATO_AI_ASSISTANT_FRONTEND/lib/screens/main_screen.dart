import 'package:flutter/material.dart';
import 'disease_detection_screen.dart';
import 'soil_analysis_screen.dart';
import 'results_screen.dart';
import 'api_test_screen.dart';
import '../services/api_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  String? _userEmail;

  final List<Widget> _screens = [
    const DiseaseDetectionScreen(),
    const SoilStatusScreen(),
    const ResultsScreen(),
  ];

  // Method to change screen programmatically
  void _changeScreen(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    if (ApiService.isAuthenticated) {
      try {
        final profile = await ApiService.getUserProfile();
        setState(() {
          _userEmail = profile['user']['email'];
        });
      } catch (e) {
        print('Failed to load user profile: $e');
      }
    }
  }

  void _showDeveloperOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Developer Options',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.api),
                title: const Text('API Test'),
                subtitle: const Text('Test all backend endpoints'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ConnectionTestScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                subtitle: const Text('Sign out from current account'),
                onTap: () {
                  Navigator.pop(context);
                  _logout();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ApiService.logout();
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tomato AI Assistant'),
            if (_userEmail != null)
              Text(
                _userEmail!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          // Hidden developer menu (long press)
          IconButton(
            icon: const Icon(Icons.developer_mode),
            onPressed: () => _showDeveloperOptions(context),
            tooltip: 'Developer Options',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens.map((screen) {
          // Pass the changeScreen function to each screen
          if (screen is DiseaseDetectionScreen) {
            return DiseaseDetectionScreen(
              onProceed: () => _changeScreen(1), // Go to Soil Analysis
            );
          } else if (screen is SoilStatusScreen) {
            return SoilStatusScreen(
              onProceed: () => _changeScreen(2), // Go to Results
            );
          }
          return screen;
        }).toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_camera),
            label: 'Disease Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.thermostat),
            label: 'Soil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights),
            label: 'Results',
          ),
        ],
      ),
    );
  }
}