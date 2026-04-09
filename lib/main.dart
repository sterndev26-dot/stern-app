import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'services/ble/ble_service.dart';
import 'services/database/database_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SternApp());
}

class SternApp extends StatefulWidget {
  const SternApp({super.key});

  @override
  State<SternApp> createState() => _SternAppState();
}

class _SternAppState extends State<SternApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BleService().startAdapterMonitoring();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // App is closing — clean up resources
      BleService().dispose();
      DatabaseService().close();
    }
    if (state == AppLifecycleState.paused) {
      // App goes to background — stop scan to save battery
      BleService().stopScan();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BleService().dispose();
    DatabaseService().close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stern',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
