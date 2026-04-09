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

enum NearByFilter { nearBy, newDevices, fromDb }

class _ScannedProductsScreenState extends State<ScannedProductsScreen> {
  static const _appBlue = Color(0xFF1A73E8);

  final BleService _bleService = BleService();
  final DatabaseService _db = DatabaseService();

  final List<SternProduct> _products = [];
  List<SternProduct> _filteredProducts = [];
  NearByFilter _filter = NearByFilter.nearBy;
  StreamSubscription<SternProduct?>? _scanSub;
  bool _isScanning = false;
  bool _showSearch = false;
  String _searchQuery = '';
  final Set<SternTypes> _typeFilters = {};
  bool _showTypeFilter = false;
  List<SternProduct> _dbProducts = [];

  @override
  void initState() {
    super.initState();
    _loadDb();
    _startScan();
  }

  Future<void> _loadDb() async {
    _dbProducts = await _db.getAllProducts();
    if (_filter == NearByFilter.fromDb) {
      setState(() => _filteredProducts = List.from(_dbProducts));
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _products.clear();
      _filteredProducts.clear();
    });

    _scanSub?.cancel();
    _scanSub = _bleService.scanResults.listen((product) {
      if (!mounted) return;
      if (product == null) {
        setState(() => _isScanning = false);
        return;
      }
      final alreadyExists = _products.any((p) => p.macAddress == product.macAddress);
      if (alreadyExists) return;

      product.isPreviouslyConnected =
          _dbProducts.any((p) => p.macAddress == product.macAddress);

      setState(() {
        _products.add(product);
        _applyFilter();
      });
    });

    await _bleService.startScan();
  }

  void _applyFilter() {
    List<SternProduct> source;
    switch (_filter) {
      case NearByFilter.nearBy:
        source = List.from(_products);
      case NearByFilter.newDevices:
        source = _products.where((p) => !p.isPreviouslyConnected).toList();
      case NearByFilter.fromDb:
        source = List.from(_dbProducts);
    }

    if (_typeFilters.isNotEmpty) {
      source = source.where((p) => _typeFilters.contains(p.type)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      source = source
          .where((p) =>
              p.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    _filteredProducts = source;
  }

  Future<void> _deleteProduct(SternProduct product) async {
    if (product.macAddress != null) {
      await _db.deleteByMacAddress(product.macAddress!);
    }
    setState(() {
      _products.removeWhere((p) => p.macAddress == product.macAddress);
      _dbProducts.removeWhere((p) => p.macAddress == product.macAddress);
      _applyFilter();
    });
  }

  void _onProductTapped(SternProduct product) {
    _bleService.stopScan();
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
        return 'Admin';
      case UserType.cleaner:
        return 'Guest';
      case UserType.undefined:
        return '';
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _bleService.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          if (_showSearch) _buildSearchBar(),
          if (_showTypeFilter) _buildTypeFilterRow(),
          const Divider(height: 1),
          Expanded(child: _buildProductList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: _appBlue,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => showDialog(
                        context: context,
                        builder: (_) => const _HelpDialog()),
                    child: Image.asset('assets/images/help.png',
                        width: 28, height: 28),
                  ),
                  const Spacer(),
                  const Text('STERN',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
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
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('Log Out',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_userLabel,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showSearch = !_showSearch),
                    child: Image.asset('assets/images/search.png',
                        width: 32, height: 28),
                  ),
                  const SizedBox(width: 8),
                  _filterChip('Near By', NearByFilter.nearBy),
                  const SizedBox(width: 8),
                  _filterChip('New', NearByFilter.newDevices),
                  const Spacer(),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showTypeFilter = !_showTypeFilter),
                    child: Image.asset('assets/images/filter.png',
                        width: 32, height: 28),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, NearByFilter value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() {
        _filter = value;
        _applyFilter();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.yellow : Colors.white,
                fontSize: 14)),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        autofocus: true,
        decoration:
            const InputDecoration(hintText: 'Search...', border: InputBorder.none),
        onChanged: (v) => setState(() {
          _searchQuery = v;
          _applyFilter();
        }),
      ),
    );
  }

  Widget _buildTypeFilterRow() {
    return Container(
      height: 60,
      color: Colors.grey[100],
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: SternTypes.values.map((type) {
          final selected = _typeFilters.contains(type);
          return GestureDetector(
            onTap: () => setState(() {
              if (selected) {
                _typeFilters.remove(type);
              } else {
                _typeFilters.add(type);
              }
              _applyFilter();
            }),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                border:
                    Border.all(color: selected ? _appBlue : Colors.grey),
                borderRadius: BorderRadius.circular(8),
                color: selected
                    ? _appBlue.withValues(alpha: 0.1)
                    : Colors.white,
              ),
              child: Image.asset(type.imagePath, width: 36, height: 36),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProductList() {
    if (_filteredProducts.isEmpty) {
      return Center(
        child: _isScanning
            ? const CircularProgressIndicator(color: _appBlue)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/images/sternblucon.png',
                      width: 80, height: 80),
                  const SizedBox(height: 16),
                  const Text('No devices found',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  TextButton(
                      onPressed: _startScan,
                      child: const Text('Scan Again')),
                ],
              ),
      );
    }

    return RefreshIndicator(
      onRefresh: _startScan,
      child: ListView.builder(
        itemCount: _filteredProducts.length,
        itemBuilder: (ctx, i) {
          final product = _filteredProducts[i];
          return Dismissible(
            key: Key(product.macAddress ?? '$i'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Text('Delete',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            onDismissed: (_) => _deleteProduct(product),
            child: _ProductTile(
                product: product,
                onTap: () => _onProductTapped(product)),
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final SternProduct product;
  final VoidCallback onTap;

  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Image.asset(product.imagePath, width: 44, height: 44),
      title: Text(product.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: product.lastConnected != null
          ? Text(product.lastConnected!)
          : null,
      trailing: product.isPreviouslyConnected
          ? const Icon(Icons.star, color: Color(0xFF1A73E8), size: 18)
          : null,
    );
  }
}

class _HelpDialog extends StatelessWidget {
  const _HelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Help'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Near By — show devices in range'),
          SizedBox(height: 8),
          Text('New — show devices not yet paired'),
          SizedBox(height: 8),
          Text('Filter icon — filter by device type'),
          SizedBox(height: 8),
          Text('Swipe left on a device to delete it'),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'))
      ],
    );
  }
}
