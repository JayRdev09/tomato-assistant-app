import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/main_screen.dart';
import 'screens/api_test_screen.dart';

void main() {
  runApp(const TomatoAIApp());
}

class TomatoAIApp extends StatelessWidget {
  const TomatoAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tomato AI Assistant',
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/main': (context) => const MainScreen(),
        '/test': (context) => const ConnectionTestScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}