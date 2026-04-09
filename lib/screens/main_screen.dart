import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/user.dart';
import 'operate_screen.dart';
import 'statistics_screen.dart';
import 'settings_screen.dart';
import 'product_information_screen.dart';

class MainScreen extends StatefulWidget {
  final SternProduct product;

  const MainScreen({super.key, required this.product});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _appBlue = Color(0xFF1A73E8);
  int _currentIndex = 0;

  bool get _isTechnician => User.instance.isTechnician;

  List<Widget> get _screens => [
        OperateScreen(product: widget.product),
        StatisticsScreen(product: widget.product),
        if (_isTechnician) SettingsScreen(product: widget.product),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _screens[_currentIndex]),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: _appBlue,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Image.asset('assets/images/arrow.png',
                    width: 28, height: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.product.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const Text('Settings',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        ProductInformationScreen(product: widget.product))),
                child: const Icon(Icons.info_outline,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => showDialog(
                    context: context,
                    builder: (_) => const _HelpDialog()),
                child: Image.asset('assets/images/help.png',
                    width: 28, height: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
          icon: Icon(Icons.play_circle_outline), label: 'Operate'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart), label: 'Statistics'),
      if (_isTechnician)
        const BottomNavigationBarItem(
            icon: Icon(Icons.settings), label: 'Settings'),
    ];

    return BottomNavigationBar(
      currentIndex: _currentIndex,
      selectedItemColor: _appBlue,
      unselectedItemColor: Colors.grey,
      onTap: (i) => setState(() => _currentIndex = i),
      items: items,
    );
  }
}

class _HelpDialog extends StatelessWidget {
  const _HelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Help'),
      content: const Text(
          'Use the tabs below to Operate, view Statistics, or configure Settings for this device.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK')),
      ],
    );
  }
}
