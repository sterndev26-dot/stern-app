import 'package:flutter/material.dart';
import '../models/user.dart';
import '../utils/constants.dart';
import 'scanned_products_screen.dart';

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _passwordController = TextEditingController();
  bool _isConnectEnabled = false;

  static const _appBlue = Color(0xFF1A73E8);

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _onPasswordChanged(String value) {
    setState(() => _isConnectEnabled = value.isNotEmpty);
  }

  Future<void> _onConnect() async {
    final password = _passwordController.text;
    if (password == AppConstants.sharedPrefTechnicianPassword) {
      await User.instance.loginAsTechnician();
      _goToMain();
    } else {
      _showWrongPasswordDialog();
    }
  }

  Future<void> _onGuestConnect() async {
    await User.instance.loginAsCleaner();
    _goToMain();
  }

  void _goToMain() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ScannedProductsScreen()),
    );
  }

  void _showWrongPasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Wrong Password'),
        content: const Text('The password you entered is incorrect.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/neutral_app_opening.png', fit: BoxFit.cover),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _passwordController,
                          obscureText: true,
                          onChanged: _onPasswordChanged,
                          onSubmitted: (_) { if (_isConnectEnabled) _onConnect(); },
                          decoration: const InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderSide: BorderSide.none),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _isConnectEnabled ? _onConnect : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: _isConnectEnabled ? _appBlue : Colors.grey,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Connect',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _onGuestConnect,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _appBlue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Guest Connect',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
