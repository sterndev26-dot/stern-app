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
  static const _appVersion = '1.0.67';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Show splash for 2 seconds while requesting permissions in background
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final granted = await PermissionService().requestBlePermissions();
    if (!mounted) return;

    if (!granted) {
      _showPermissionDeniedDialog();
      return;
    }

    final hasSession = await User.instance.loadSavedSession();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => hasSession
            ? const ScannedProductsScreen()
            : const PasswordScreen(),
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Bluetooth Required'),
        content: const Text(
          'Stern App requires Bluetooth access to connect to hygiene products.\n\n'
          'Please enable Bluetooth permissions in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _init();
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
      body: SafeArea(
        child: Column(
          children: [
            // ── Main image — centered, takes most of the screen ──
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Image.asset(
                    'assets/images/splash_screen_img.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            // ── Bottom: Powered By + Version ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Powered By MSApps logo
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'POWERED BY',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Image.asset(
                        'assets/images/powerded_by.png',
                        height: 28,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),

                  // Version bottom-right
                  Text(
                    'Version: $_appVersion',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
