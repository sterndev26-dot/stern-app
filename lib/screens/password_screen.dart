import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isError = false;

  static const String TECHNICIAN_PASSWORD = '4321';

  void _onPasswordSubmit() async {
    final password = _passwordController.text;

    if (password == TECHNICIAN_PASSWORD) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('user_type_set', true);
      await prefs.setString('user_type', 'technician');

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/main');
    } else {
      setState(() => _isError = true);
      _passwordController.clear();
    }
  }

  void _onGuestConnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('user_type_set', true);
    await prefs.setString('user_type', 'guest');

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/main');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo.png', height: 120),
              const SizedBox(height: 40),
              TextField(
                controller: _passwordController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 4,
                decoration: InputDecoration(
                  hintText: 'Enter Password',
                  errorText: _isError ? 'The password is wrong' : null,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _onPasswordSubmit(),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _onPasswordSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text(
                  'Connect',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _onGuestConnect,
                child: const Text(
                  'Connect as Guest',
                  style: TextStyle(color: Colors.blue, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
