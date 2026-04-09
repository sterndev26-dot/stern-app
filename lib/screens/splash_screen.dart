import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/ble/permission_service.dart';
import 'password_screen.dart';
import 'scanned_products_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    // Request BLE permissions before anything else
    setState(() => _statusText = 'Requesting permissions...');
    final granted = await PermissionService().requestBlePermissions();

    if (!mounted) return;

    if (!granted) {
      _showPermissionDeniedDialog();
      return;
    }

    // Check saved session
    setState(() => _statusText = '');
    final hasSession = await User.instance.loadSavedSession();
    if (!mounted) return;

    if (hasSession) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ScannedProductsScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PasswordScreen()),
      );
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Bluetooth Required'),
        content: const Text(
          'Stern App requires Bluetooth access to connect to hygiene products.\n\nPlease enable Bluetooth permissions in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _init(); // retry
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/splash_screen_img.png',
              fit: BoxFit.contain,
              height: 200,
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Color(0xFF1A73E8)),
            const SizedBox(height: 20),
            if (_statusText.isNotEmpty)
              Text(_statusText,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Text(
              'Version: 1.0.67',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
