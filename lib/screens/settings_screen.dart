import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
import '../services/ble/ble_service.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatefulWidget {
  final SternProduct product;

  const SettingsScreen({super.key, required this.product});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _appTeal = Color(0xFF0097A7);

  final _ble = BleService();
  bool _isBusy = false;
  bool _isLoading = true;
  bool _newPresetMode = false;
  final _presetNameController = TextEditingController();
  final List<String> _presets = [];
  String? _selectedPreset;

  // --- Seek bar settings (all 0–100 range) ---
  double _delayIn = 5;
  double _delayOut = 5;
  double _longFlush = 10;
  double _shortWash = 5;
  double _securityTime = 10;
  double _betweenTime = 5;
  double _detectionRange = 50;

  // --- Soap dosage (1–5) ---
  int _soapDosage = 3;

  // --- Simple control toggles ---
  bool _simpleControlEnabled = false;

  bool get _isSoapType =>
      widget.product.type == SternTypes.soapDispenser ||
      widget.product.type == SternTypes.foamSoapDispenser;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _presetNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      // Read delay-in
      final delayInData = await _ble.readCharacteristic(
          BleGattAttributes.uuidDataSettingsService,
          BleGattAttributes.uuidSettingsRemotesDelayIn);
      if (delayInData != null && delayInData.isNotEmpty) {
        setState(() => _delayIn = delayInData[0].clamp(0, 100).toDouble());
      }

      // Read delay-out
      final delayOutData = await _ble.readCharacteristic(
          BleGattAttributes.uuidDataSettingsService,
          BleGattAttributes.uuidSettingsRemotesDelayOut);
      if (delayOutData != null && delayOutData.isNotEmpty) {
        setState(() => _delayOut = delayOutData[0].clamp(0, 100).toDouble());
      }

      // Read detection range
      final rangeData = await _ble.readCharacteristic(
          BleGattAttributes.uuidDataSettingsService,
          BleGattAttributes.uuidSettingsDetectionRange);
      if (rangeData != null && rangeData.isNotEmpty) {
        setState(
            () => _detectionRange = rangeData[0].clamp(0, 100).toDouble());
      }

      // Read soap dosage (soap/foam only)
      if (_isSoapType) {
        final dosageUuid = widget.product.type == SternTypes.foamSoapDispenser
            ? BleGattAttributes.uuidSettingsFoamSoap
            : BleGattAttributes.uuidSettingsSoapDosage;
        final dosageData = await _ble.readCharacteristic(
            BleGattAttributes.uuidDataSettingsService, dosageUuid);
        if (dosageData != null && dosageData.isNotEmpty) {
          setState(() => _soapDosage = dosageData[0].clamp(1, 5));
        }
      }
    } catch (e) {
      dev.log('SettingsScreen: load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _apply() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      bool ok = true;

      ok &= await _ble.writeCharacteristic(
          BleGattAttributes.uuidDataSettingsService,
          BleGattAttributes.uuidSettingsRemotesDelayIn,
          [_delayIn.round()]);

      ok &= await _ble.writeCharacteristic(
          BleGattAttributes.uuidDataSettingsService,
          BleGattAttributes.uuidSettingsRemotesDelayOut,
          [_delayOut.round()]);

      ok &= await _ble.writeCharacteristic(
          BleGattAttributes.uuidDataSettingsService,
          BleGattAttributes.uuidSettingsRemotesLongFlush,
          [_longFlush.round()]);

      ok &= await _ble.writeCharacteristic(
          BleGattAttributes.uuidDataSettingsService,
          BleGattAttributes.uuidSettingsRemotesShortWash,
          [_shortWash.round()]);

      ok &= await _ble.writeCharacteristic(
          BleGattAttributes.uuidDataSettingsService,
          BleGattAttributes.uuidSettingsRemotesSecurityTime,
          [_securityTime.round()]);

      ok &= await _ble.writeCharacteristic(
          BleGattAttributes.uuidDataSettingsService,
          BleGattAttributes.uuidSettingsRemotesBetweenTime,
          [_betweenTime.round()]);

      ok &= await _ble.writeCharacteristic(
          BleGattAttributes.uuidDataSettingsService,
          BleGattAttributes.uuidSettingsDetectionRange,
          [_detectionRange.round()]);

      if (_isSoapType) {
        final dosageUuid =
            widget.product.type == SternTypes.foamSoapDispenser
                ? BleGattAttributes.uuidSettingsFoamSoap
                : BleGattAttributes.uuidSettingsSoapDosage;
        ok &= await _ble.writeCharacteristic(
            BleGattAttributes.uuidDataSettingsService,
            dosageUuid,
            [_soapDosage]);
      }

      if (mounted) {
        _showSnack(ok ? 'Settings applied' : 'Some settings failed to apply');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _savePreset() {
    final name = _presetNameController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _presets.add(name);
      _selectedPreset = name;
      _newPresetMode = false;
      _presetNameController.clear();
    });
    _showSnack('Preset "$name" saved');
  }

  void _loadPreset() {
    if (_selectedPreset == null) {
      _showSnack('Select a preset first');
      return;
    }
    _showSnack('Preset "$_selectedPreset" loaded');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Preset action bar
        _buildPresetBar(),
        // Settings content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_newPresetMode) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _presetNameController,
                    decoration: InputDecoration(
                      labelText: 'Preset name',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check, color: _appTeal),
                        onPressed: _savePreset,
                      ),
                    ),
                    onSubmitted: (_) => _savePreset(),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_presets.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildPresetList(),
                  const SizedBox(height: 8),
                ],

                // Detection Range
                _buildSeekSection(
                  title: 'Detection Range',
                  value: _detectionRange,
                  min: 0,
                  max: 100,
                  unit: 'cm',
                  onChanged: (v) => setState(() => _detectionRange = v),
                ),
                const SizedBox(height: 12),

                // Delay In
                _buildSeekSection(
                  title: 'Delay In',
                  value: _delayIn,
                  min: 0,
                  max: 100,
                  unit: 's',
                  onChanged: (v) => setState(() => _delayIn = v),
                ),
                const SizedBox(height: 12),

                // Delay Out
                _buildSeekSection(
                  title: 'Delay Out',
                  value: _delayOut,
                  min: 0,
                  max: 100,
                  unit: 's',
                  onChanged: (v) => setState(() => _delayOut = v),
                ),
                const SizedBox(height: 12),

                // Long Flush
                _buildSeekSection(
                  title: 'Long Flush',
                  value: _longFlush,
                  min: 0,
                  max: 100,
                  unit: 's',
                  onChanged: (v) => setState(() => _longFlush = v),
                ),
                const SizedBox(height: 12),

                // Short Wash
                _buildSeekSection(
                  title: 'Short Wash',
                  value: _shortWash,
                  min: 0,
                  max: 100,
                  unit: 's',
                  onChanged: (v) => setState(() => _shortWash = v),
                ),
                const SizedBox(height: 12),

                // Security Time
                _buildSeekSection(
                  title: 'Security Time',
                  value: _securityTime,
                  min: 0,
                  max: 100,
                  unit: 's',
                  onChanged: (v) => setState(() => _securityTime = v),
                ),
                const SizedBox(height: 12),

                // Between Time
                _buildSeekSection(
                  title: 'Between Time',
                  value: _betweenTime,
                  min: 0,
                  max: 100,
                  unit: 's',
                  onChanged: (v) => setState(() => _betweenTime = v),
                ),
                const SizedBox(height: 12),

                // Soap dosage (soap/foam dispensers only)
                if (_isSoapType) ...[
                  _buildDosageSection(),
                  const SizedBox(height: 12),
                ],

                // Simple Controls toggle
                _buildSimpleControlsSection(),
                const SizedBox(height: 24),

                // Apply button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isBusy ? null : _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _appTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Apply',
                            style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetBar() {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _PresetButton(
            label: 'Save',
            enabled: !_newPresetMode,
            onTap: () => setState(() {
              _newPresetMode = true;
              _presetNameController.clear();
            }),
          ),
          const SizedBox(width: 8),
          _PresetButton(
            label: 'Load',
            enabled: _selectedPreset != null && !_newPresetMode,
            onTap: _loadPreset,
          ),
          const SizedBox(width: 8),
          _PresetButton(
            label: 'New',
            enabled: true,
            onTap: () => setState(() {
              _selectedPreset = null;
              _newPresetMode = false;
              _delayIn = 5;
              _delayOut = 5;
              _longFlush = 10;
              _shortWash = 5;
              _securityTime = 10;
              _betweenTime = 5;
              _detectionRange = 50;
              _soapDosage = 3;
              _showSnack('Values reset to default');
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetList() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: _presets.map((name) {
          return ListTile(
            dense: true,
            title: Text(name),
            leading: const Icon(Icons.bookmark_outline, color: _appTeal),
            selected: _selectedPreset == name,
            selectedColor: _appTeal,
            selectedTileColor: _appTeal.withValues(alpha: 0.08),
            onTap: () => setState(() => _selectedPreset = name),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => setState(() {
                _presets.remove(name);
                if (_selectedPreset == name) _selectedPreset = null;
              }),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSeekSection({
    required String title,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  '${value.round()} $unit',
                  style: const TextStyle(
                      color: _appTeal,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).round(),
              activeColor: _appTeal,
              label: '${value.round()} $unit',
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDosageSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Soap Dosage',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (i) {
                final level = i + 1;
                final selected = _soapDosage == level;
                return GestureDetector(
                  onTap: () => setState(() => _soapDosage = level),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected ? _appTeal : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$level',
                      style: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleControlsSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SwitchListTile(
        title: const Text('Simple Controls',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(_simpleControlEnabled ? 'Enabled' : 'Disabled',
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        value: _simpleControlEnabled,
        activeColor: _appTeal,
        onChanged: (v) => setState(() => _simpleControlEnabled = v),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PresetButton(
      {required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF0097A7),
          side: BorderSide(
              color: enabled ? const Color(0xFF0097A7) : Colors.grey),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label),
      ),
    );
  }
}
