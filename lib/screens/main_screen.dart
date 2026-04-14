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

  List<Widget> get _tabs => [
        _DeviceInfoTab(product: widget.product),
        OperateScreen(product: widget.product),
        if (_isTechnician) SettingsScreen(product: widget.product),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _tabs[_currentIndex]),
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
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              // Back = disconnect + return to scan list
              GestureDetector(
                onTap: _disconnectAndGoBack,
                child: const Icon(Icons.arrow_back,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              // Product icon
              Image.asset(widget.product.imagePath,
                  width: 36, height: 36),
              const SizedBox(width: 10),
              // Product name + type
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.product.type.displayName,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Help button
              GestureDetector(
                onTap: () => showDialog(
                    context: context,
                    builder: (_) => const _HelpDialog()),
                child: const Icon(Icons.help_outline,
                    color: Colors.white, size: 26),
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
        icon: Icon(Icons.assignment_outlined),
        activeIcon: Icon(Icons.assignment),
        label: 'Info',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.handyman_outlined),
        activeIcon: Icon(Icons.handyman),
        label: 'Operate',
      ),
      if (_isTechnician)
        const BottomNavigationBarItem(
          icon: Icon(Icons.tune),
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _nameController.text = _product.name;
    _loadDeviceInfo().then((_) {
      if (mounted) _showDateTimeSyncDialog();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── Date/Time Sync ────────────────────────────────

  void _showDateTimeSyncDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.access_time, color: _appTeal),
            SizedBox(width: 8),
            Text('Sync Date & Time',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
            'Update the device clock to the current date and time?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _syncDateTime();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _appTeal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncDateTime() async {
    final now = DateTime.now();
    final packet = [
      now.second & 0xFF,
      now.minute & 0xFF,
      now.hour & 0xFF,
      now.day & 0xFF,
      now.month & 0xFF,
      (now.year - 2000) & 0xFF,
    ];

    final ok = await _ble.writeCharacteristic(
      BleGattAttributes.uuidCalenderService,
      BleGattAttributes.uuidCalenderCharacteristicReadWrite,
      packet,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            ok ? 'Date & time updated' : 'Failed to update date & time'),
        backgroundColor: ok ? _appTeal : Colors.red,
        duration: const Duration(seconds: 2),
      ));
    }

    if (ok && mounted) await _loadDeviceInfo();
  }

  // ── BLE Load ──────────────────────────────────────

  Future<void> _loadDeviceInfo() async {
    if (mounted) setState(() => _isLoading = true);

    // Information characteristic: name, serial, SW version, battery
    final infoData = await _ble.readCharacteristic(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidInformationRead,
    );

    if (infoData != null && mounted) {
      final hexStr = _parser.bytesToHexString(infoData);
      final deviceName = _parser.getName(hexStr);
      final serial = _parser.parseSerialNumber(hexStr);
      final sw = _parser.parseSoftwareVersion(hexStr);
      final battery = _parser.parseBatteryVoltage(infoData);
      final mfgDate = _parser.getDate(hexStr);

      setState(() {
        if (deviceName != null && deviceName.isNotEmpty) {
          _product.name = deviceName;
          _nameController.text = deviceName;
        }
        if (serial != null) _product.serialNumber = serial;
        if (sw != null) _product.swVersion = sw;
        if (battery != null) _product.batteryVoltage = battery;
        if (mfgDate != null) _product.lastUpdate = _parser.formatDate(mfgDate);
      });

      await _db.updateProduct(_product);
    }

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

    // Valve state
    final operateData = await _ble.readCharacteristic(
      BleGattAttributes.uuidDataOperateService,
      BleGattAttributes.uuidOperateReadWrite,
    );
    if (operateData != null && mounted) {
      setState(() =>
          _product.valveState = _parser.parseValveState(operateData));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Name updated'),
        backgroundColor: _appTeal,
        duration: Duration(seconds: 2),
      ));
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date/time sync button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _showDateTimeSyncDialog,
                icon: const Icon(Icons.access_time, size: 18),
                label: const Text('Sync Time'),
                style: TextButton.styleFrom(foregroundColor: _appTeal),
              ),
            ),
            const SizedBox(height: 4),

            // Product Name (editable for technician)
            _buildNameField(),
            const SizedBox(height: 8),

            // Info rows
            _infoRow(Icons.qr_code_outlined, 'Serial Number',
                _product.serialNumber ?? '—'),
            _infoRow(Icons.memory_outlined, 'BLE SW Version',
                _product.swVersion ?? '—'),
            _infoRow(Icons.battery_charging_full_outlined, 'Battery',
                _product.batteryVoltage ?? '—'),
            _infoRow(Icons.lock_open_outlined, 'Valve State',
                _product.valveState ?? '—'),
            _infoRow(Icons.calendar_today_outlined, 'Device Date & Time',
                _product.lastUpdate ?? '—'),
            _infoRow(Icons.bluetooth_connected, 'Last Connected',
                _product.lastConnected ?? '—'),
            _infoRow(Icons.category_outlined, 'Product Type',
                _product.type.displayName),
            if (_product.dayleUsage != null)
              _infoRow(Icons.water_drop_outlined, 'Daily Usage',
                  _product.dayleUsage!),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField() {
    final isTechnician = User.instance.isTechnician;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Product Name',
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                enabled: _isEditingName,
                maxLength: _maxNameLength,
                decoration: InputDecoration(
                  counterText: _isEditingName ? null : '',
                  errorText: _nameError,
                  border: _isEditingName
                      ? const OutlineInputBorder()
                      : InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
                onSubmitted: (_) => _submitName(),
              ),
            ),
            if (isTechnician) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _onEditPressed,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Icon(
                    _isEditingName ? Icons.check_circle : Icons.edit,
                    color: _appTeal,
                    size: 24,
                  ),
                ),
              ),
            ],
          ],
        ),
        const Divider(color: Color(0xFFE0E0E0)),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: _appTeal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Center(
                    child: Text('Information',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
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
        _bullet('Manual Activation:',
            ' Allows the user to activate unit manually for a set duration of time, as specified by the user.'),
        _bullet('Hygiene Flush Activation:',
            ' Allows user to set a flush that activates automatically after a defined period of non-use, as specified by the user.'),
        _bullet('Schedule Hygiene Flush:',
            ' Allows user to schedule a flush at a specific time on a given day or date for a set duration, as specified by the user.'),
        _bullet('Manual Standby Activation:',
            ' User can disable the sensor for a set duration of time, as specified by the user.'),
        _bullet('Schedule Standby:',
            ' User can schedule a standby at a specified time on a given day or date for a set duration, as specified by the user.'),
        _bullet('Detection Range:',
            ' This is the range within which the user can be detected in front of the sensor.'),
        _bullet('Delay In:',
            ' This is the amount of time that the user needs to be in the sensor detection range before they are recognized by the sensor, preventing premature activation.'),
        _bullet('Delay Out:',
            ' The amount of time that needs to pass after the user leaves the sensor detection range, before the sensor recognizes that the user has left, preventing premature activations.'),
        _bullet('Security Time:',
            ' This is the maximum amount of time that a sensor will allow the valve to remain open, preventing continuous flow.'),
        _sectionTitle('Soap Dispenser'),
        _bullet('Soap Dosage:',
            ' This is the amount of soap dispensed per activation, as specified by the user.'),
        _sectionTitle('Foam Dispenser'),
        _bullet('Air Quantity:',
            ' This is the amount of air compressed into the soap to create foam, as specified by the user.'),
        _bullet('Soap Quantity:',
            ' This is the amount of soap compressed with air to produce foam, as specified by the user.'),
        _sectionTitle('Flush Valve'),
        _bullet('Flush Time:',
            ' This is the amount of time that the valve remains open for a full flush, as specified by the user.'),
        _bullet('Short Flush Time:',
            ' This is the amount of time that the valve stays open for a half flush, as specified by the user.'),
        _sectionTitle('Wave Sensor'),
        _bullet('Flow time:',
            ' This is the amount of time that the sensor will keep the valve open, as specified by the user.'),
      ],
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline)),
      );

  Widget _bullet(String bold, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
                fontSize: 14, color: Colors.black87, height: 1.4),
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
