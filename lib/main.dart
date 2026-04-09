import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'screens/password_screen.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(const SternApp());
}

class SternApp extends StatelessWidget {
  const SternApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stern',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/password': (context) => const PasswordScreen(),
        '/main': (context) => const MainScreen(),
      },
    );
  }
}
