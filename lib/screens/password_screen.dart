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
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen background image
          Image.asset(
            'assets/images/neutral_app_opening.png',
            fit: BoxFit.cover,
          ),
          // Content overlay
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                // Input area at the bottom
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Password row: field + Connect button
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _passwordController,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              onChanged: _onPasswordChanged,
                              onSubmitted: (_) {
                                if (_isConnectEnabled) _onConnect();
                              },
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white,
                                hintText: 'Password',
                                hintStyle: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _isConnectEnabled ? _onConnect : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: _isConnectEnabled
                                    ? _appBlue
                                    : Colors.grey[400],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Connect',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Guest Connect full-width button
                      GestureDetector(
                        onTap: _onGuestConnect,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _appBlue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Guest Connect',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
