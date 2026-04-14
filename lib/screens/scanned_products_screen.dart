import 'package:flutter/material.dart';
import 'dart:async';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
import '../models/user.dart';
import '../services/ble/ble_service.dart';
import '../services/database/database_service.dart';
import 'password_screen.dart';
import 'main_screen.dart';

class ScannedProductsScreen extends StatefulWidget {
  const ScannedProductsScreen({super.key});

  @override
  State<ScannedProductsScreen> createState() => _ScannedProductsScreenState();
}

enum _Tab { configured, unconfigured }

class _ScannedProductsScreenState extends State<ScannedProductsScreen> {
  static const _appTeal = Color(0xFF0097A7);

  final BleService _bleService = BleService();
  final DatabaseService _db = DatabaseService();

  final List<SternProduct> _scannedProducts = [];
  List<SternProduct> _dbProducts = [];

  _Tab _tab = _Tab.unconfigured;
  bool _isScanning = false;
  bool _showSearch = false;
  String _searchQuery = '';
  final Set<SternTypes> _activeTypeFilters = {};
  bool _showTypeFilter = false;
  StreamSubscription<SternProduct?>? _scanSub;

  @override
  void initState() {
    super.initState();
    _loadDb();
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _bleService.stopScan();
    super.dispose();
  }

  Future<void> _loadDb() async {
    final products = await _db.getAllProducts();
    if (mounted) setState(() {
      _dbProducts = products;
      // Switch to configured if we have paired devices
      if (products.isNotEmpty) _tab = _Tab.configured;
    });
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _scannedProducts.clear();
    });

    // Cancel previous subscription before creating new one
    await _scanSub?.cancel();
    _scanSub = _bleService.scanResults.listen((product) {
      if (!mounted) return;
      if (product == null) {
        if (mounted) setState(() => _isScanning = false);
        return;
      }
      final exists = _scannedProducts.any((p) => p.macAddress == product.macAddress);
      if (!exists) {
        product.isPreviouslyConnected =
            _dbProducts.any((p) => p.macAddress == product.macAddress);
        if (mounted) setState(() => _scannedProducts.add(product));
      }
    });

    await _bleService.startScan();
    if (mounted) setState(() => _isScanning = false);
  }

  List<SternProduct> get _displayedProducts {
    List<SternProduct> source;

    switch (_tab) {
      case _Tab.configured:
        // Show DB products, mark which ones are currently nearby
        source = _dbProducts.map((p) {
          p.nearby = _scannedProducts.any((s) => s.macAddress == p.macAddress);
          return p;
        }).toList();
      case _Tab.unconfigured:
        // Show scanned products NOT in DB
        source = _scannedProducts
            .where((p) => !_dbProducts.any((d) => d.macAddress == p.macAddress))
            .toList();
    }

    if (_activeTypeFilters.isNotEmpty) {
      source = source.where((p) => _activeTypeFilters.contains(p.type)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      source = source
          .where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    return source;
  }

  Future<void> _deleteProduct(SternProduct product) async {
    if (product.macAddress != null) {
      await _db.deleteByMacAddress(product.macAddress!);
    }
    setState(() {
      _dbProducts.removeWhere((p) => p.macAddress == product.macAddress);
      _scannedProducts.removeWhere((p) => p.macAddress == product.macAddress);
    });
  }

  Future<void> _onPairTapped(SternProduct product) async {
    if (product.macAddress == null) return;
    await _bleService.stopScan();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Color(0xFF0097A7)),
            SizedBox(width: 20),
            Text('Connecting...'),
          ],
        ),
      ),
    );

    final connected = await _bleService.connectByMac(product.macAddress!);

    if (!mounted) return;
    Navigator.of(context).pop();

    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect. Try again.')),
      );
      return;
    }

    final now = DateTime.now().toString();
    product.lastConnected = now;
    product.isPreviouslyConnected = true;

    final existing = await _db.getProductByMac(product.macAddress!);
    if (existing != null) {
      existing.lastConnected = now;
      existing.nearby = true;
      await _db.updateProduct(existing);
    } else {
      await _db.insertProduct(product);
      setState(() {
        if (!_dbProducts.any((p) => p.macAddress == product.macAddress)) {
          _dbProducts.add(product);
        }
      });
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MainScreen(product: product)),
    );
  }

  Future<void> _logOut() async {
    await _bleService.stopScan();
    await User.instance.logOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PasswordScreen()),
    );
  }

  String get _userLabel {
    switch (User.instance.userType) {
      case UserType.technician:
        return 'Admin User';
      case UserType.cleaner:
        return 'Guest User';
      case UserType.undefined:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(),
          if (_showSearch) _buildSearchBar(),
          if (_showTypeFilter) _buildTypeFilterRow(),
          const Divider(height: 1, color: Color(0xFFE0E0E0)),
          Expanded(child: _buildProductList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: _appTeal,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            children: [
              // Row 1: help | My Products | Log Out / user
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Help icon
                  GestureDetector(
                    onTap: () => showDialog(
                        context: context,
                        builder: (_) => const _HelpDialog()),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.help_outline,
                          color: Colors.white, size: 28),
                    ),
                  ),
                  // Title
                  const Expanded(
                    child: Center(
                      child: Text(
                        'My Products',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Log Out + user label
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: _logOut,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Log Out',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(_userLabel,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Row 2: search | Configured | Unconfigured | filter
              Row(
                children: [
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showSearch = !_showSearch),
                    child: const Icon(Icons.search,
                        color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 10),
                  _tabChip('Configured', _Tab.configured),
                  const SizedBox(width: 8),
                  _tabChip('Unconfigured', _Tab.unconfigured),
                  const Spacer(),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showTypeFilter = !_showTypeFilter),
                    child: const Icon(Icons.filter_list,
                        color: Colors.white, size: 30),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabChip(String label, _Tab value) {
    final selected = _tab == value;
    return GestureDetector(
      onTap: () => setState(() {
        _tab = value;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF00E5FF) : Colors.white,
            fontSize: 14,
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search by name...',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search, color: Colors.grey),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildTypeFilterRow() {
    return Container(
      height: 70,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: SternTypes.values
            .where((t) => t != SternTypes.unpluggedConnectors)
            .map((type) {
          final selected = _activeTypeFilters.contains(type);
          return GestureDetector(
            onTap: () => setState(() {
              if (selected) {
                _activeTypeFilters.remove(type);
              } else {
                _activeTypeFilters.add(type);
              }
            }),
            child: Opacity(
              opacity: selected ? 1.0 : 0.4,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Image.asset(type.imagePath, width: 44, height: 44),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProductList() {
    final products = _displayedProducts;

    if (products.isEmpty) {
      return RefreshIndicator(
        onRefresh: _startScan,
        color: _appTeal,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: _isScanning
                    ? const CircularProgressIndicator(color: _appTeal)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bluetooth_searching,
                              size: 72, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            _tab == _Tab.configured
                                ? 'No configured products'
                                : 'No products found in proximity',
                            style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pull down to scan',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 13),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _startScan,
      color: _appTeal,
      child: ListView.separated(
        itemCount: products.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFFE0E0E0)),
        itemBuilder: (ctx, i) {
          final product = products[i];
          return Dismissible(
            key: Key(product.macAddress ?? '$i'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) => _deleteProduct(product),
            child: _ProductTile(
              product: product,
              onPair: () => _onPairTapped(product),
            ),
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final SternProduct product;
  final VoidCallback onPair;

  const _ProductTile({required this.product, required this.onPair});

  @override
  Widget build(BuildContext context) {
    final snDisplay = product.serialNumber != null
        ? 'S/N:  ${product.serialNumber}'
        : product.macAddress != null
            ? 'S/N:  ${product.macAddress}'
            : '';

    final lastUpdated = product.lastConnected != null
        ? 'Last updated:  ${product.lastConnected}'
        : 'Last updated:';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Image.asset(product.imagePath, width: 52, height: 52),
          const SizedBox(width: 12),
          // Text info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(snDisplay,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(lastUpdated,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Pair button
          OutlinedButton(
            onPressed: onPair,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0097A7),
              side: const BorderSide(color: Color(0xFF0097A7)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            ),
            child: const Text('Pair',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _HelpDialog extends StatelessWidget {
  const _HelpDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0097A7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Center(
                    child: Text(
                      'Information',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text('Close',
                      style: TextStyle(color: Colors.white, fontSize: 15)),
                ),
              ],
            ),
          ),
          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _helpContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpContent() {
    const items = [
      _HelpItem(
        bold: 'Manual Activation:',
        text:
            ' Allows the user to activate unit manually for a set duration of time, as specified by the user.',
      ),
      _HelpItem(
        bold: 'Hygiene Flush Activation:',
        text:
            ' Allows user to set a flush that activates automatically after a defined period of non-use, as specified by the user.',
      ),
      _HelpItem(
        bold: 'Schedule Hygiene Flush:',
        text:
            ' Allows user to schedule a flush at a specific time on a given day or date for a set duration, as specified by the user.',
      ),
      _HelpItem(
        bold: 'Manual Standby Activation:',
        text:
            ' User can disable the sensor for a set duration of time, as specified by the user.',
      ),
      _HelpItem(
        bold: 'Schedule Standby:',
        text:
            ' User can schedule a standby at a specified time on a given day or date for a set duration, as specified by the user.',
      ),
      _HelpItem(
        bold: 'Detection Range:',
        text:
            ' This is the range within which the user can be detected in front of the sensor.',
      ),
      _HelpItem(
        bold: 'Delay In:',
        text:
            ' This is the amount of time that the user needs to be in the sensor detection range before they are recognized by the sensor, preventing premature activation.',
      ),
      _HelpItem(
        bold: 'Delay Out:',
        text:
            ' The amount of time that needs to pass after the user leaves the sensor detection range, before the sensor recognizes that the user has left, preventing premature activations.',
      ),
      _HelpItem(
        bold: 'Security Time:',
        text:
            ' This is the maximum amount of time that a sensor will allow the valve to remain open, preventing continuous flow.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 14, color: Colors.black87, height: 1.4),
                  children: [
                    const TextSpan(text: '• '),
                    TextSpan(
                        text: item.bold,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: item.text),
                  ],
                ),
              ),
            )),
        _sectionTitle('Soap Dispenser'),
        _bulletItem('Soap Dosage:',
            ' This is the amount of soap dispensed per activation, as specified by the user.'),
        _sectionTitle('Foam Dispenser'),
        _bulletItem('Air Quantity:',
            ' This is the amount of air compressed into the soap to create foam, as specified by the user.'),
        _bulletItem('Soap Quantity:',
            ' This is the amount of soap compressed with air to produce foam, as specified by the user.'),
        _sectionTitle('Flush Valve'),
        _bulletItem('Flush Time:',
            ' This is the amount of time that the valve remains open for a full flush, as specified by the user.'),
        _bulletItem('Short Flush Time:',
            ' This is the amount of time that the valve stays open for a half flush, as specified by the user.'),
        _sectionTitle('Wave Sensor'),
        _bulletItem('Flow time:',
            ' This is the amount of time that the sensor will keep the valve open, as specified by the user.'),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _bulletItem(String bold, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          style:
              const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
          children: [
            const TextSpan(text: '• '),
            TextSpan(
                text: bold,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }
}

class _HelpItem {
  final String bold;
  final String text;
  const _HelpItem({required this.bold, required this.text});
}
