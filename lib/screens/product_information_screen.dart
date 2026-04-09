import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
import '../models/user.dart';
import '../services/ble/ble_service.dart';
import '../services/ble/ble_data_parser.dart';
import '../services/database/database_service.dart';
import '../utils/constants.dart';

class ProductInformationScreen extends StatefulWidget {
  final SternProduct product;

  const ProductInformationScreen({super.key, required this.product});

  @override
  State<ProductInformationScreen> createState() =>
      _ProductInformationScreenState();
}

class _ProductInformationScreenState extends State<ProductInformationScreen> {
  static const _appBlue = Color(0xFF1A73E8);
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
    _loadDeviceInfo();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── BLE data loading ──────────────────────────────

  Future<void> _loadDeviceInfo() async {
    setState(() => _isLoading = true);

    // Read information characteristic
    final infoData = await _ble.readCharacteristic(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidInformationRead,
    );

    if (infoData != null && mounted) {
      final hexStr = _parser.bytesToHexString(infoData);
      final serial = _parser.parseSerialNumber(hexStr);
      final sw = _parser.parseSoftwareVersion(infoData);
      final mfgDate = _parser.getDate(hexStr);
      final battery = _parser.parseBatteryVoltage(infoData);

      setState(() {
        if (serial != null) _product.serialNumber = serial;
        if (sw != null) _product.swVersion = sw;
        if (mfgDate != null) _product.lastUpdate = _parser.formatDate(mfgDate);
        if (battery != null) _product.batteryVoltage = battery;
      });

      // Persist updated info
      await _db.updateProduct(_product);
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
      setState(() => _nameError = 'Name too long (max $_maxNameLength chars)');
      return;
    }
    // Reject special characters (matching Android regex)
    final invalid = RegExp(r'[$&+,:;=?@#|/<>.^*()%!\-]');
    if (invalid.hasMatch(name)) {
      setState(() => _nameError = 'Name contains invalid characters');
      return;
    }

    setState(() {
      _isEditingName = false;
      _nameError = null;
      _product.name = name;
    });
    _nameFocus.unfocus();

    // Write name via BLE
    await _ble.writeCharacteristic(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidInformationWrite,
      name.codeUnits,
    );

    // Persist to local DB
    await _db.updateProduct(_product);
  }

  // ── UI ───────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _appBlue))
                : _buildInfoList(),
          ),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Image.asset('assets/images/arrow.png',
                        width: 28, height: 28),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _showHelp,
                    child: Image.asset('assets/images/help.png',
                        width: 28, height: 28),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Product type title
              Center(
                child: Text(
                  _product.type.displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text('Information',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNameField(),
          const SizedBox(height: 16),
          _infoRow('Product Type', _product.type.displayName),
          _infoRow('Serial Number', _product.serialNumber ?? '—'),
          _infoRow('Software Version', _product.swVersion ?? '—'),
          _infoRow('Battery', _product.batteryVoltage ?? '—'),
          _infoRow('Valve State', _product.valveState ?? '—'),
          _infoRow('Last Connected', _product.lastConnected ?? '—'),
          _infoRow('Last Update', _product.lastUpdate ?? '—'),
          _infoRow('Last Filter Clean', _product.lastFilterClean ?? '—'),
          _infoRow('Daily Usage', _product.dayleUsage ?? '—'),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    final isTechnician = User.instance.isTechnician;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Product Name',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              TextField(
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
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                ),
                style: TextStyle(
                  fontSize: 16,
                  color: _nameError != null ? Colors.red : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
                onSubmitted: (_) => _submitName(),
              ),
            ],
          ),
        ),
        if (isTechnician) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _onEditPressed,
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Icon(
                _isEditingName ? Icons.send : Icons.edit,
                color: _appBlue,
                size: 24,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                  fontSize: 16, fontWeight: FontWeight.w500)),
          const Divider(height: 1, color: Color(0xFFE0E0E0)),
        ],
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Product Information'),
        content: const Text(
            'This screen shows the technical information of the connected Stern device.\n\n'
            'Tap the edit icon next to the name to rename the device.\n\n'
            'Pull to refresh to reload data from the device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }
}
