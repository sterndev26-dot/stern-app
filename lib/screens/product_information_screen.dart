import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
import '../models/user.dart';
import '../services/ble/ble_service.dart';
import '../services/ble/ble_data_parser.dart';
import '../services/database/database_service.dart';
import '../utils/constants.dart';
import 'main_screen.dart';

class ProductInformationScreen extends StatefulWidget {
  final SternProduct product;
  /// true = came from ScannedProducts (first entry), false = came from MainScreen info button
  final bool isFirstEntry;

  const ProductInformationScreen({
    super.key,
    required this.product,
    this.isFirstEntry = false,
  });

  @override
  State<ProductInformationScreen> createState() =>
      _ProductInformationScreenState();
}

class _ProductInformationScreenState extends State<ProductInformationScreen> {
  static const _appTeal = Color(0xFF0097A7);
  static const _maxNameLength = 22;

  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _isEditingName = false;
  bool _isLoading = true;
  String? _nameError;

  late SternProduct _product;

  final _ble = BleService();
  final _db = DatabaseService();
  final _parser = BleDataParser();

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _nameController.text = _product.name;
    _loadDeviceInfo().then((_) {
      if (widget.isFirstEntry && mounted) {
        _showDateTimeSyncDialog();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── Date/Time sync ────────────────────────────────

  void _showDateTimeSyncDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.access_time, color: _appTeal),
            SizedBox(width: 10),
            Text('Sync Date & Time',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Update the device clock to the current date and time?',
          style: TextStyle(fontSize: 14, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip',
                style: TextStyle(color: Colors.grey)),
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
    // Calendar format: [sec, min, hr, day, month, year-2000]
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Date & time updated successfully'
              : 'Failed to update date & time'),
          backgroundColor: ok ? _appTeal : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Reload device info after sync so the displayed time is fresh
    if (ok && mounted) {
      await _loadDeviceInfo();
    }
  }

  // ── BLE data loading ──────────────────────────────

  Future<void> _loadDeviceInfo() async {
    if (mounted) setState(() => _isLoading = true);

    // Read information characteristic (name, serial, SW version, battery)
    final infoData = await _ble.readCharacteristic(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidInformationRead,
    );

    if (infoData != null && mounted) {
      final hexStr = _parser.bytesToHexString(infoData);
      final deviceName = _parser.getName(hexStr);
      final serial = _parser.parseSerialNumber(hexStr);
      final sw = _parser.parseSoftwareVersion(hexStr);
      final mfgDate = _parser.getDate(hexStr);
      final battery = _parser.parseBatteryVoltage(infoData);

      setState(() {
        if (deviceName != null && deviceName.isNotEmpty) {
          _product.name = deviceName;
          _nameController.text = deviceName;
        }
        if (serial != null) _product.serialNumber = serial;
        if (sw != null) _product.swVersion = sw;
        if (mfgDate != null) _product.lastUpdate = _parser.formatDate(mfgDate);
        if (battery != null) _product.batteryVoltage = battery;
      });

      await _db.updateProduct(_product);
    }

    // Read current device date/time from calendar characteristic
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

    // Read valve state from operate characteristic
    final operateData = await _ble.readCharacteristic(
      BleGattAttributes.uuidDataOperateService,
      BleGattAttributes.uuidOperateReadWrite,
    );
    if (operateData != null && mounted) {
      setState(() {
        _product.valveState = _parser.parseValveState(operateData);
      });
    }

    // Read scheduled (last hygiene flush)
    final schedData = await _ble.readCharacteristic(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidScheduledCharacteristic,
    );
    if (schedData != null && mounted) {
      final hexStr = _parser.bytesToHexString(schedData);
      final dt = _parser.getDate(hexStr);
      if (dt != null) {
        setState(() => _product.lastFilterClean = _parser.formatDate(dt));
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ── Name editing ──────────────────────────────────

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
      setState(() => _nameError = 'Invalid characters in name');
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
            duration: Duration(seconds: 2)),
      );
    }
  }

  void _goToManage() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => MainScreen(product: _product)),
    );
  }

  // ── UI ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _appTeal))
                : _buildContent(),
          ),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(
            children: [
              Row(
                children: [
                  if (!widget.isFirstEntry)
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 26),
                    )
                  else
                    const SizedBox(width: 26),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showDateTimeSyncDialog(),
                    child: const Icon(Icons.access_time,
                        color: Colors.white, size: 26),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Product icon + type name
              Image.asset(_product.imagePath, width: 56, height: 56),
              const SizedBox(height: 6),
              Text(
                _product.type.displayName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              const Text('Device Information',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Info rows
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNameField(),
                _infoRow(Icons.category_outlined, 'Product Type',
                    _product.type.displayName),
                _infoRow(Icons.qr_code, 'Serial Number',
                    _product.serialNumber ?? '—'),
                _infoRow(Icons.code, 'Software Version',
                    _product.swVersion ?? '—'),
                _infoRow(Icons.battery_charging_full, 'Battery',
                    _product.batteryVoltage ?? '—'),
                _infoRow(Icons.lock_open_outlined, 'Valve State',
                    _product.valveState ?? '—'),
                _infoRow(Icons.calendar_today, 'Device Date & Time',
                    _product.lastUpdate ?? '—'),
                _infoRow(Icons.history, 'Last Filter Clean',
                    _product.lastFilterClean ?? '—'),
                _infoRow(Icons.bluetooth_connected, 'Last Connected',
                    _product.lastConnected ?? '—'),
                _infoRow(Icons.water_drop_outlined, 'Daily Usage',
                    _product.dayleUsage ?? '—'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Manage Device button (only shown on first entry)
          if (widget.isFirstEntry)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _goToManage,
                  icon: const Icon(Icons.settings),
                  label: const Text('Manage Device',
                      style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _appTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),

          if (!widget.isFirstEntry) const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    final isTechnician = User.instance.isTechnician;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
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
                    padding: const EdgeInsets.only(top: 12),
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
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
