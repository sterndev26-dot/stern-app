import 'dart:async';
import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
import '../models/user.dart';
import '../services/ble/ble_service.dart';
import '../services/ble/ble_data_parser.dart';
import '../services/database/database_service.dart';
import '../utils/constants.dart';
import 'operate_screen.dart';
import 'settings_screen.dart';
import 'scanned_products_screen.dart';
import 'debug_log_screen.dart';

class MainScreen extends StatefulWidget {
  final SternProduct product;

  const MainScreen({super.key, required this.product});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _appTeal = Color(0xFF0097A7);
  int _currentIndex = 0;
  late final List<Widget> _tabs;

  bool get _isTechnician => User.instance.isTechnician;

  @override
  void initState() {
    super.initState();
    _tabs = [
      _DeviceInfoTab(product: widget.product),
      OperateScreen(product: widget.product),
      if (_isTechnician) SettingsScreen(product: widget.product),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [_buildHeader(), Expanded(child: _tabs[_currentIndex])],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: _appTeal,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: back arrow | product type centered
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Back arrow left
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: _disconnectAndGoBack,
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  // Product type name centered
                  Text(
                    widget.product.type.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Row 2: help icon (left) + debug icon (right)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap:
                        () => showDialog(
                          context: context,
                          builder: (_) => const _HelpDialog(),
                        ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.question_mark,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DebugLogScreen(),
                          ),
                        ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.bug_report_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
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

  Widget _buildBottomNav() {
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.checklist_outlined),
        activeIcon: Icon(Icons.checklist),
        label: '',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.handyman_outlined),
        activeIcon: Icon(Icons.handyman),
        label: '',
      ),
      if (_isTechnician)
        const BottomNavigationBarItem(
          icon: Icon(Icons.tune),
          activeIcon: Icon(Icons.tune),
          label: '',
        ),
    ];

    return BottomNavigationBar(
      currentIndex: _currentIndex,
      selectedItemColor: _appTeal,
      unselectedItemColor: Colors.grey,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      onTap: (i) => setState(() => _currentIndex = i),
      items: items,
    );
  }

  Future<void> _disconnectAndGoBack() async {
    await BleService().disconnect();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ScannedProductsScreen()),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Device Info Tab (Tab 0)
// ─────────────────────────────────────────────────────────────

class _DeviceInfoTab extends StatefulWidget {
  final SternProduct product;
  const _DeviceInfoTab({required this.product});

  @override
  State<_DeviceInfoTab> createState() => _DeviceInfoTabState();
}

class _DeviceInfoTabState extends State<_DeviceInfoTab>
    with AutomaticKeepAliveClientMixin {
  static const _appTeal = Color(0xFF0097A7);
  static const _maxNameLength = 22;

  final _ble = BleService();
  final _db = DatabaseService();
  final _parser = BleDataParser();
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  late SternProduct _product;
  bool _isLoading = true;
  bool _isEditingName = false;
  String? _nameError;
  String? _mfgDate; // production date from info characteristic

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _nameController.text = _product.name;
    _loadDeviceInfo();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── BLE Load ──────────────────────────────────────

  Future<void> _loadDeviceInfo() async {
    if (mounted) setState(() => _isLoading = true);

    // Request each field from 0x1303 using Stern BLE protocol:
    // write [field_id + 0x80] → device responds with notification [field_id+0x80, ...data]

    // 0x85 = SW version [0x85, patch, minor, major]
    final swData = await _ble.requestCharacteristicField(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidInformationRead,
      0x85,
    );
    if (swData != null && mounted) {
      final sw = _parser.parseSoftwareVersion(_parser.bytesToHexString(swData));
      if (sw != null) setState(() => _product.swVersion = sw);
    }

    // 0x81 = device name [0x81, ...ascii, 0x24, 0x26]
    final nameData = await _ble.requestCharacteristicField(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidInformationRead,
      0x81,
    );
    if (nameData != null && mounted) {
      final name = _parser.getName(_parser.bytesToHexString(nameData));
      if (name != null && name.isNotEmpty) {
        setState(() {
          _product.name = name;
          _nameController.text = name;
        });
      }
    }

    // 0x83 = serial number [0x83, b0, b1, b2, b3] (ulong little-endian)
    final serialData = await _ble.requestCharacteristicField(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidInformationRead,
      0x83,
    );
    if (serialData != null && mounted) {
      final serial = _parser.parseSerialNumber(
        _parser.bytesToHexString(serialData),
      );
      if (serial != null) setState(() => _product.serialNumber = serial);
    }

    // 0x84 = production date [0x84, sec, min, hr, day, month, year]
    final prodDateData = await _ble.requestCharacteristicField(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidInformationRead,
      0x84,
    );
    if (prodDateData != null && mounted) {
      final dt = _parser.getDate(_parser.bytesToHexString(prodDateData));
      if (dt != null) setState(() => _mfgDate = _parser.formatDate(dt));
    }

    if (mounted) await _db.updateProduct(_product);

    // Calendar: current device date/time
    final calData = await _ble.readCharacteristic(
      BleGattAttributes.uuidCalenderService,
      BleGattAttributes.uuidCalenderCharacteristicReadWrite,
    );
    if (calData != null && mounted) {
      final hexStr = _parser.bytesToHexString(calData);
      final dt = _parser.getDate(hexStr, isCalendarDate: true);
      if (dt != null) {
        setState(() => _product.lastUpdate = _parser.formatDate(dt));
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ── Name Edit ─────────────────────────────────────

  void _onEditPressed() {
    if (!_isEditingName) {
      setState(() {
        _isEditingName = true;
        _nameError = null;
      });
      Future.delayed(const Duration(milliseconds: 50), () {
        _nameFocus.requestFocus();
        _nameController.selection = TextSelection.fromPosition(
          TextPosition(offset: _nameController.text.length),
        );
      });
    } else {
      _submitName();
    }
  }

  Future<void> _submitName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Name cannot be empty');
      return;
    }
    if (name.length > _maxNameLength) {
      setState(() => _nameError = 'Max $_maxNameLength characters');
      return;
    }
    final invalid = RegExp(r'[$&+,:;=?@#|/<>.^*()%!\-]');
    if (invalid.hasMatch(name)) {
      setState(() => _nameError = 'Invalid characters');
      return;
    }

    setState(() {
      _isEditingName = false;
      _nameError = null;
      _product.name = name;
    });
    _nameFocus.unfocus();

    await _ble.writeCharacteristic(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidInformationRead,
      _parser.nameToBytes(name),
    );
    await _db.updateProduct(_product);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name updated'),
          backgroundColor: _appTeal,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ── UI ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _appTeal));
    }

    return RefreshIndicator(
      onRefresh: _loadDeviceInfo,
      color: _appTeal,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Name (editable)
            _buildNameField(),

            // Product Type | Serial Number
            _twoColRow(
              'Product Type',
              _product.type.displayName,
              'Serial Number',
              _product.serialNumber ?? '—',
            ),

            // BLE SW Version (full width with update date on right)
            _swVersionRow(),

            // Date | First Pairing Date
            _twoColRow(
              'Date',
              _product.lastUpdate ?? '—',
              'First Pairing Date',
              _formatPairingDate(_product.lastConnected),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPairingDate(String? raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw);
      return _parser.formatDate(dt);
    } catch (_) {
      return raw;
    }
  }

  Widget _buildNameField() {
    final isTechnician = User.instance.isTechnician;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Product Name',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child:
                  _isEditingName
                      ? TextField(
                        controller: _nameController,
                        focusNode: _nameFocus,
                        maxLength: _maxNameLength,
                        decoration: InputDecoration(
                          errorText: _nameError,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        style: const TextStyle(fontSize: 16),
                        onSubmitted: (_) => _submitName(),
                      )
                      : Text(
                        _nameController.text,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: isTechnician ? _onEditPressed : null,
              child: Icon(
                _isEditingName ? Icons.check : Icons.edit,
                color: isTechnician ? Colors.black87 : Colors.transparent,
                size: 22,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(color: Color(0xFFDDDDDD), height: 1),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _twoColRow(String label1, String val1, String label2, String val2) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _labelValue(label1, val1)),
            Expanded(child: _labelValue(label2, val2)),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(color: Color(0xFFDDDDDD), height: 1),
      ],
    );
  }

  Widget _swVersionRow() {
    // Shows: "BLE SW Version" label full-width
    // Then: version on left, update date on right
    return Column(
      children: [
        const SizedBox(height: 12),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'BLE SW Version',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _product.swVersion ?? '—',
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
            ),
            Text(
              _mfgDate ?? '—',
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(color: Color(0xFFDDDDDD), height: 1),
      ],
    );
  }

  Widget _labelValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 15, color: Colors.black87),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Help Dialog
// ─────────────────────────────────────────────────────────────

class _HelpDialog extends StatelessWidget {
  const _HelpDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0097A7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Center(
                    child: Text(
                      'Information',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildHelpContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bullet(
          'Manual Activation:',
          ' Allows the user to activate unit manually for a set duration of time, as specified by the user.',
        ),
        _bullet(
          'Hygiene Flush Activation:',
          ' Allows user to set a flush that activates automatically after a defined period of non-use, as specified by the user.',
        ),
        _bullet(
          'Schedule Hygiene Flush:',
          ' Allows user to schedule a flush at a specific time on a given day or date for a set duration, as specified by the user.',
        ),
        _bullet(
          'Manual Standby Activation:',
          ' User can disable the sensor for a set duration of time, as specified by the user.',
        ),
        _bullet(
          'Schedule Standby:',
          ' User can schedule a standby at a specified time on a given day or date for a set duration, as specified by the user.',
        ),
        _bullet(
          'Detection Range:',
          ' This is the range within which the user can be detected in front of the sensor.',
        ),
        _bullet(
          'Delay In:',
          ' This is the amount of time that the user needs to be in the sensor detection range before they are recognized by the sensor, preventing premature activation.',
        ),
        _bullet(
          'Delay Out:',
          ' The amount of time that needs to pass after the user leaves the sensor detection range, before the sensor recognizes that the user has left, preventing premature activations.',
        ),
        _bullet(
          'Security Time:',
          ' This is the maximum amount of time that a sensor will allow the valve to remain open, preventing continuous flow.',
        ),
        _sectionTitle('Soap Dispenser'),
        _bullet(
          'Soap Dosage:',
          ' This is the amount of soap dispensed per activation, as specified by the user.',
        ),
        _sectionTitle('Foam Dispenser'),
        _bullet(
          'Air Quantity:',
          ' This is the amount of air compressed into the soap to create foam, as specified by the user.',
        ),
        _bullet(
          'Soap Quantity:',
          ' This is the amount of soap compressed with air to produce foam, as specified by the user.',
        ),
        _sectionTitle('Flush Valve'),
        _bullet(
          'Flush Time:',
          ' This is the amount of time that the valve remains open for a full flush, as specified by the user.',
        ),
        _bullet(
          'Short Flush Time:',
          ' This is the amount of time that the valve stays open for a half flush, as specified by the user.',
        ),
        _sectionTitle('Wave Sensor'),
        _bullet(
          'Flow time:',
          ' This is the amount of time that the sensor will keep the valve open, as specified by the user.',
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.underline,
      ),
    ),
  );

  Widget _bullet(String bold, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black87,
          height: 1.4,
        ),
        children: [
          const TextSpan(text: '• '),
          TextSpan(
            text: bold,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: text),
        ],
      ),
    ),
  );
}
