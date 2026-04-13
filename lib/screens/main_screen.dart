import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
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
  static const _appTeal = Color(0xFF0097A7);
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
      color: _appTeal,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              // Back arrow
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Image.asset('assets/images/arrow.png',
                    width: 28, height: 28),
              ),
              const SizedBox(width: 12),
              // Product type icon
              Image.asset(
                widget.product.imagePath,
                width: 36,
                height: 36,
              ),
              const SizedBox(width: 10),
              // Product name + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.product.type.displayName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // Info icon
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ProductInformationScreen(product: widget.product),
                  ),
                ),
                child: const Icon(Icons.info_outline,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              // Help icon
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
      BottomNavigationBarItem(
        icon: ImageIcon(
          const AssetImage('assets/images/aperatedea.png'),
          size: 28,
        ),
        label: 'Operate',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.bar_chart),
        label: 'Statistics',
      ),
      if (_isTechnician)
        BottomNavigationBarItem(
          icon: ImageIcon(
            const AssetImage('assets/images/settingsdea.png'),
            size: 28,
          ),
          label: 'Settings',
        ),
    ];

    return BottomNavigationBar(
      currentIndex: _currentIndex,
      selectedItemColor: _appTeal,
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
