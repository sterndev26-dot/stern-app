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

  // --- Seek bar settings (seconds, float) ---
  double _delayIn = 1.0;
  double _delayOut = 1.0;
  double _longFlush = 5.0;
  double _shortWash = 3.0;
  double _securityTime = 10.0;
  double _betweenTime = 5.0;
  double _detectionRange = 5.0;

  // --- Dynamic slider ranges (updated from device response) ---
  double _delayInMax = 30;
  double _delayOutMax = 30;
  double _longFlushMax = 60;
  double _shortWashMax = 30;
  double _securityTimeMax = 120;
  double _betweenTimeMax = 120;
  double _detectionRangeMax = 18;

  // --- Soap dosage (1–5) ---
  int _soapDosage = 3;

  // --- Simple control toggle ---
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

  // ─── BLE helpers ───────────────────────────────────────────────────────────

  /// Parse a 4-byte little-endian int32 starting at [offset].
  static int _le32(List<int> data, int offset) {
    if (data.length < offset + 4) return 0;
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  /// Build the 5-byte write packet for time-based settings.
  /// Format: [0x01, msLo, msMidLo, msMidHi, msMidHi] — value in milliseconds.
  static List<int> _timeBytes(double seconds) {
    final ms = (seconds * 1000).round().clamp(0, 0xFFFFFF);
    return [
      0x01,
      ms & 0xFF,
      (ms >> 8) & 0xFF,
      (ms >> 16) & 0xFF,
      0x00,
    ];
  }

  // ─── Load ──────────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      const svc = BleGattAttributes.uuidDataSettingsService;

      await _readTime(svc, BleGattAttributes.uuidSettingsRemotesDelayIn,
          (v, maxV) => setState(() {
                _delayIn = v;
                if (maxV > 0) _delayInMax = maxV;
              }));

      await _readTime(svc, BleGattAttributes.uuidSettingsRemotesDelayOut,
          (v, maxV) => setState(() {
                _delayOut = v;
                if (maxV > 0) _delayOutMax = maxV;
              }));

      await _readTime(svc, BleGattAttributes.uuidSettingsRemotesLongFlush,
          (v, maxV) => setState(() {
                _longFlush = v;
                if (maxV > 0) _longFlushMax = maxV;
              }));

      await _readTime(svc, BleGattAttributes.uuidSettingsRemotesShortWash,
          (v, maxV) => setState(() {
                _shortWash = v;
                if (maxV > 0) _shortWashMax = maxV;
              }));

      await _readTime(svc, BleGattAttributes.uuidSettingsRemotesSecurityTime,
          (v, maxV) => setState(() {
                _securityTime = v;
                if (maxV > 0) _securityTimeMax = maxV;
              }));

      await _readTime(svc, BleGattAttributes.uuidSettingsRemotesBetweenTime,
          (v, maxV) => setState(() {
                _betweenTime = v;
                if (maxV > 0) _betweenTimeMax = maxV;
              }));

      // Detection range: [echo, currentSteps, maxSteps, ...]
      final rangeData = await _ble.requestCharacteristicField(
          svc, BleGattAttributes.uuidSettingsDetectionRange, 0x81);
      if (rangeData != null && rangeData.length >= 2) {
        setState(() {
          _detectionRange = rangeData[1].toDouble().clamp(1, 100);
          if (rangeData.length >= 3 && rangeData[2] > 0) {
            _detectionRangeMax = rangeData[2].toDouble();
          }
        });
      }

      // Simple controls: [echo, 0/1]
      final simpleData = await _ble.requestCharacteristicField(
          svc, BleGattAttributes.uuidSettingsSimpleControls, 0x81);
      if (simpleData != null && simpleData.length >= 2) {
        setState(() => _simpleControlEnabled = simpleData[1] != 0);
      }

      // Soap dosage (soap/foam only)
      if (_isSoapType) {
        final dosageUuid = widget.product.type == SternTypes.foamSoapDispenser
            ? BleGattAttributes.uuidSettingsFoamSoap
            : BleGattAttributes.uuidSettingsSoapDosage;
        final dosageData = await _ble.requestCharacteristicField(
            svc, dosageUuid, 0x81);
        if (dosageData != null && dosageData.length >= 2) {
          setState(() => _soapDosage = dosageData[1].clamp(1, 5));
        }
      }
    } catch (e) {
      dev.log('SettingsScreen: load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Read a time-based setting characteristic.
  /// Response: [echo(0x81), b1, b2, b3, b4 = currentMs LE32,
  ///            b5..b8 = maxMs LE32, b9..b12 = minMs LE32, ...]
  Future<void> _readTime(
    String svc,
    String char,
    void Function(double value, double maxValue) onParsed,
  ) async {
    try {
      final data = await _ble.requestCharacteristicField(svc, char, 0x81);
      if (data == null || data.length < 5) return;

      final currentMs = _le32(data, 1);
      final currentSec = currentMs / 1000.0;

      double maxSec = 0;
      if (data.length >= 9) {
        final maxMs = _le32(data, 5);
        maxSec = maxMs / 1000.0;
      }

      onParsed(currentSec, maxSec);
    } catch (e) {
      dev.log('_readTime [$char]: $e');
    }
  }

  // ─── Apply ─────────────────────────────────────────────────────────────────

  Future<void> _apply() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      bool ok = true;
      const svc = BleGattAttributes.uuidDataSettingsService;

      // Time-based settings: [0x01, msLo, msMidLo, msMidHi, 0x00]
      ok &= await _ble.writeCharacteristic(
          svc, BleGattAttributes.uuidSettingsRemotesDelayIn,
          _timeBytes(_delayIn));

      ok &= await _ble.writeCharacteristic(
          svc, BleGattAttributes.uuidSettingsRemotesDelayOut,
          _timeBytes(_delayOut));

      ok &= await _ble.writeCharacteristic(
          svc, BleGattAttributes.uuidSettingsRemotesLongFlush,
          _timeBytes(_longFlush));

      ok &= await _ble.writeCharacteristic(
          svc, BleGattAttributes.uuidSettingsRemotesShortWash,
          _timeBytes(_shortWash));

      ok &= await _ble.writeCharacteristic(
          svc, BleGattAttributes.uuidSettingsRemotesSecurityTime,
          _timeBytes(_securityTime));

      ok &= await _ble.writeCharacteristic(
          svc, BleGattAttributes.uuidSettingsRemotesBetweenTime,
          _timeBytes(_betweenTime));

      // Detection range: [0x01, steps]
      ok &= await _ble.writeCharacteristic(
          svc, BleGattAttributes.uuidSettingsDetectionRange,
          [0x01, _detectionRange.round()]);

      // Simple controls: [0x01, 0/1]
      ok &= await _ble.writeCharacteristic(
          svc, BleGattAttributes.uuidSettingsSimpleControls,
          [0x01, _simpleControlEnabled ? 1 : 0]);

      // Soap dosage: [0x01, dosage]
      if (_isSoapType) {
        final dosageUuid =
            widget.product.type == SternTypes.foamSoapDispenser
                ? BleGattAttributes.uuidSettingsFoamSoap
                : BleGattAttributes.uuidSettingsSoapDosage;
        ok &= await _ble.writeCharacteristic(
            svc, dosageUuid, [0x01, _soapDosage]);
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

  // ─── Presets ───────────────────────────────────────────────────────────────

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

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _buildPresetBar(),
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

                _buildSeekSection(
                  title: 'Detection Range',
                  value: _detectionRange,
                  min: 1,
                  max: _detectionRangeMax,
                  unit: 'steps',
                  decimals: 0,
                  onChanged: (v) => setState(() => _detectionRange = v),
                ),
                const SizedBox(height: 12),

                _buildSeekSection(
                  title: 'Delay In',
                  value: _delayIn,
                  min: 0,
                  max: _delayInMax,
                  unit: 's',
                  decimals: 1,
                  onChanged: (v) => setState(() => _delayIn = v),
                ),
                const SizedBox(height: 12),

                _buildSeekSection(
                  title: 'Delay Out',
                  value: _delayOut,
                  min: 0,
                  max: _delayOutMax,
                  unit: 's',
                  decimals: 1,
                  onChanged: (v) => setState(() => _delayOut = v),
                ),
                const SizedBox(height: 12),

                _buildSeekSection(
                  title: 'Long Flush',
                  value: _longFlush,
                  min: 0,
                  max: _longFlushMax,
                  unit: 's',
                  decimals: 1,
                  onChanged: (v) => setState(() => _longFlush = v),
                ),
                const SizedBox(height: 12),

                _buildSeekSection(
                  title: 'Short Wash',
                  value: _shortWash,
                  min: 0,
                  max: _shortWashMax,
                  unit: 's',
                  decimals: 1,
                  onChanged: (v) => setState(() => _shortWash = v),
                ),
                const SizedBox(height: 12),

                _buildSeekSection(
                  title: 'Security Time',
                  value: _securityTime,
                  min: 0,
                  max: _securityTimeMax,
                  unit: 's',
                  decimals: 0,
                  onChanged: (v) => setState(() => _securityTime = v),
                ),
                const SizedBox(height: 12),

                _buildSeekSection(
                  title: 'Between Time',
                  value: _betweenTime,
                  min: 0,
                  max: _betweenTimeMax,
                  unit: 's',
                  decimals: 0,
                  onChanged: (v) => setState(() => _betweenTime = v),
                ),
                const SizedBox(height: 12),

                if (_isSoapType) ...[
                  _buildDosageSection(),
                  const SizedBox(height: 12),
                ],

                _buildSimpleControlsSection(),
                const SizedBox(height: 24),

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
              _delayIn = 1.0;
              _delayOut = 1.0;
              _longFlush = 5.0;
              _shortWash = 3.0;
              _securityTime = 10.0;
              _betweenTime = 5.0;
              _detectionRange = 5.0;
              _soapDosage = 3;
              _simpleControlEnabled = false;
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
    required int decimals,
    required ValueChanged<double> onChanged,
  }) {
    final displayMax = max > 0 ? max : 100.0;
    final clampedValue = value.clamp(min, displayMax);
    final valueLabel = decimals > 0
        ? '${clampedValue.toStringAsFixed(decimals)} $unit'
        : '${clampedValue.round()} $unit';

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
                  valueLabel,
                  style: const TextStyle(
                      color: _appTeal,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ],
            ),
            Slider(
              value: clampedValue,
              min: min,
              max: displayMax,
              // Use enough divisions for smooth steps
              divisions: decimals > 0
                  ? ((displayMax - min) * 10).round().clamp(1, 200)
                  : (displayMax - min).round().clamp(1, 200),
              activeColor: _appTeal,
              label: valueLabel,
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
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
