import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
import '../services/ble/ble_service.dart';
import '../utils/constants.dart';

// Which settings a product type supports.
class _ProductSettings {
  final bool detectionRange;
  final bool delayIn;
  final bool delayOut;
  final bool shortFlush;
  final bool longFlush;
  final String longFlushLabel; // "Long Flush" | "Flush" | "Flash"
  final bool securityTime;
  final String securityTimeLabel; // "Security Time" | "Discharge"
  final bool soapDosage; // integer 1-4
  final bool airMotor;  // foam soap motor 0-9

  const _ProductSettings({
    this.detectionRange = false,
    this.delayIn = false,
    this.delayOut = false,
    this.shortFlush = false,
    this.longFlush = false,
    this.longFlushLabel = 'Long Flush',
    this.securityTime = false,
    this.securityTimeLabel = 'Security Time',
    this.soapDosage = false,
    this.airMotor = false,
  });

  static _ProductSettings forType(SternTypes type) {
    switch (type) {
      case SternTypes.faucet:
        return const _ProductSettings(
          detectionRange: true, delayIn: true, delayOut: true, securityTime: true);
      case SternTypes.shower:
        return const _ProductSettings(
          detectionRange: true, delayIn: true, delayOut: true, securityTime: true);
      case SternTypes.wc:
        return const _ProductSettings(
          detectionRange: true, delayIn: true, delayOut: true,
          shortFlush: true, longFlush: true);
      case SternTypes.urinal:
        return const _ProductSettings(
          detectionRange: true, delayIn: true, delayOut: true,
          longFlush: true, longFlushLabel: 'Flush');
      case SternTypes.waveOnOff:
        return const _ProductSettings(
          detectionRange: true, longFlush: true, longFlushLabel: 'Flash',
          securityTime: true);
      case SternTypes.soapDispenser:
        return const _ProductSettings(
          detectionRange: true, soapDosage: true);
      case SternTypes.foamSoapDispenser:
        return const _ProductSettings(
          detectionRange: true, securityTime: true,
          securityTimeLabel: 'Discharge', airMotor: true);
      default:
        return const _ProductSettings(detectionRange: true);
    }
  }
}

class SettingsScreen extends StatefulWidget {
  final SternProduct product;

  const SettingsScreen({super.key, required this.product});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _appTeal = Color(0xFF0097A7);

  final _ble = BleService();
  late final _ProductSettings _cfg;

  bool _isBusy = false;
  bool _isLoading = true;
  bool _newPresetMode = false;
  final _presetNameController = TextEditingController();
  final List<String> _presets = [];
  String? _selectedPreset;

  // --- Setting values ---
  double _detectionRange = 5;
  double _delayIn = 1.0;
  double _delayOut = 1.0;
  double _shortFlush = 3.0;
  double _longFlush = 5.0;
  double _securityTime = 10.0;
  int _soapDosage = 1;
  double _airMotor = 5;

  // --- Dynamic slider maxima (updated from device response) ---
  double _detectionRangeMax = 18;
  double _delayInMax = 30;
  double _delayOutMax = 30;
  double _shortFlushMax = 30;
  double _longFlushMax = 60;
  double _securityTimeMax = 120;

  @override
  void initState() {
    super.initState();
    _cfg = _ProductSettings.forType(widget.product.type);
    _loadSettings();
  }

  @override
  void dispose() {
    _presetNameController.dispose();
    super.dispose();
  }

  // ─── BLE helpers ───────────────────────────────────────────────────────────

  /// Parse 4-byte little-endian int32 at [offset].
  static int _le32(List<int> data, int offset) {
    if (data.length < offset + 4) return 0;
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  /// Build 5-byte write packet for time settings.
  /// [0x01, msLo, msMidLo, msMidHi, 0x00] — value in milliseconds LE.
  static List<int> _timeBytes(double seconds) {
    final ms = (seconds * 1000).round().clamp(0, 0xFFFFFF);
    return [0x01, ms & 0xFF, (ms >> 8) & 0xFF, (ms >> 16) & 0xFF, 0x00];
  }

  // ─── Load ──────────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      const svc = BleGattAttributes.uuidDataSettingsService;

      if (_cfg.detectionRange) {
        // Response: [echo, currentSteps, maxSteps]
        final d = await _ble.requestCharacteristicField(
            svc, BleGattAttributes.uuidSettingsDetectionRange, 0x81);
        if (d != null && d.length >= 2) {
          setState(() {
            _detectionRange = d[1].toDouble().clamp(1, 100);
            if (d.length >= 3 && d[2] > 0) _detectionRangeMax = d[2].toDouble();
          });
        }
      }

      if (_cfg.delayIn) {
        await _readTime(svc, BleGattAttributes.uuidSettingsRemotesDelayIn,
            (v, mx) => setState(() { _delayIn = v; if (mx > 0) _delayInMax = mx; }));
      }

      if (_cfg.delayOut) {
        await _readTime(svc, BleGattAttributes.uuidSettingsRemotesDelayOut,
            (v, mx) => setState(() { _delayOut = v; if (mx > 0) _delayOutMax = mx; }));
      }

      if (_cfg.shortFlush) {
        await _readTime(svc, BleGattAttributes.uuidSettingsRemotesShortWash,
            (v, mx) => setState(() { _shortFlush = v; if (mx > 0) _shortFlushMax = mx; }));
      }

      if (_cfg.longFlush) {
        await _readTime(svc, BleGattAttributes.uuidSettingsRemotesLongFlush,
            (v, mx) => setState(() { _longFlush = v; if (mx > 0) _longFlushMax = mx; }));
      }

      if (_cfg.securityTime) {
        await _readTime(svc, BleGattAttributes.uuidSettingsRemotesSecurityTime,
            (v, mx) => setState(() { _securityTime = v; if (mx > 0) _securityTimeMax = mx; }));
      }

      if (_cfg.soapDosage) {
        final d = await _ble.requestCharacteristicField(
            svc, BleGattAttributes.uuidSettingsSoapDosage, 0x81);
        if (d != null && d.length >= 2) {
          setState(() => _soapDosage = d[1].clamp(1, 4));
        }
      }

      if (_cfg.airMotor) {
        // Response: [echo, soapMotor, airMotor]
        final d = await _ble.requestCharacteristicField(
            svc, BleGattAttributes.uuidSettingsFoamSoap, 0x81);
        if (d != null && d.length >= 3) {
          setState(() => _airMotor = d[2].toDouble().clamp(0, 9));
        }
      }
    } catch (e) {
      dev.log('SettingsScreen: load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Request a time characteristic (write 0x81, read LE32 millis).
  /// Response: [echo, b1..b4 = currentMs, b5..b8 = maxMs, ...]
  Future<void> _readTime(String svc, String char,
      void Function(double value, double maxValue) onParsed) async {
    try {
      final data = await _ble.requestCharacteristicField(svc, char, 0x81);
      if (data == null || data.length < 5) return;
      final currentSec = _le32(data, 1) / 1000.0;
      double maxSec = 0;
      if (data.length >= 9) maxSec = _le32(data, 5) / 1000.0;
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

      if (_cfg.detectionRange) {
        ok &= await _ble.writeCharacteristic(
            svc, BleGattAttributes.uuidSettingsDetectionRange,
            [0x01, _detectionRange.round()]);
      }

      if (_cfg.delayIn) {
        ok &= await _ble.writeCharacteristic(
            svc, BleGattAttributes.uuidSettingsRemotesDelayIn,
            _timeBytes(_delayIn));
      }

      if (_cfg.delayOut) {
        ok &= await _ble.writeCharacteristic(
            svc, BleGattAttributes.uuidSettingsRemotesDelayOut,
            _timeBytes(_delayOut));
      }

      if (_cfg.shortFlush) {
        ok &= await _ble.writeCharacteristic(
            svc, BleGattAttributes.uuidSettingsRemotesShortWash,
            _timeBytes(_shortFlush));
      }

      if (_cfg.longFlush) {
        ok &= await _ble.writeCharacteristic(
            svc, BleGattAttributes.uuidSettingsRemotesLongFlush,
            _timeBytes(_longFlush));
      }

      if (_cfg.securityTime) {
        ok &= await _ble.writeCharacteristic(
            svc, BleGattAttributes.uuidSettingsRemotesSecurityTime,
            _timeBytes(_securityTime));
      }

      if (_cfg.soapDosage) {
        // [0x01, dosage]
        ok &= await _ble.writeCharacteristic(
            svc, BleGattAttributes.uuidSettingsSoapDosage,
            [0x01, _soapDosage]);
      }

      if (_cfg.airMotor) {
        // [0x01, soapMotor=1 (default), airMotor]
        ok &= await _ble.writeCharacteristic(
            svc, BleGattAttributes.uuidSettingsFoamSoap,
            [0x01, 1, _airMotor.round()]);
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

  void _resetToDefaults() {
    setState(() {
      _selectedPreset = null;
      _newPresetMode = false;
      _detectionRange = 5;
      _delayIn = 1.0;
      _delayOut = 1.0;
      _shortFlush = 3.0;
      _longFlush = 5.0;
      _securityTime = 10.0;
      _soapDosage = 1;
      _airMotor = 5;
    });
    _showSnack('Values reset to default');
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

                // Detection Range
                if (_cfg.detectionRange) ...[
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
                ],

                // Delay In
                if (_cfg.delayIn) ...[
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
                ],

                // Delay Out
                if (_cfg.delayOut) ...[
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
                ],

                // Short Flush (WC only)
                if (_cfg.shortFlush) ...[
                  _buildSeekSection(
                    title: 'Short Flush',
                    value: _shortFlush,
                    min: 0,
                    max: _shortFlushMax,
                    unit: 's',
                    decimals: 1,
                    onChanged: (v) => setState(() => _shortFlush = v),
                  ),
                  const SizedBox(height: 12),
                ],

                // Long Flush / Flush / Flash
                if (_cfg.longFlush) ...[
                  _buildSeekSection(
                    title: _cfg.longFlushLabel,
                    value: _longFlush,
                    min: 0,
                    max: _longFlushMax,
                    unit: 's',
                    decimals: 1,
                    onChanged: (v) => setState(() => _longFlush = v),
                  ),
                  const SizedBox(height: 12),
                ],

                // Security Time / Discharge
                if (_cfg.securityTime) ...[
                  _buildSeekSection(
                    title: _cfg.securityTimeLabel,
                    value: _securityTime,
                    min: 0,
                    max: _securityTimeMax,
                    unit: 's',
                    decimals: 0,
                    onChanged: (v) => setState(() => _securityTime = v),
                  ),
                  const SizedBox(height: 12),
                ],

                // Soap Dosage (Soap Dispenser only)
                if (_cfg.soapDosage) ...[
                  _buildDosageSection(),
                  const SizedBox(height: 12),
                ],

                // Air Motor (Foam Soap Dispenser only)
                if (_cfg.airMotor) ...[
                  _buildSeekSection(
                    title: 'Motor Speed',
                    value: _airMotor,
                    min: 0,
                    max: 9,
                    unit: '',
                    decimals: 0,
                    onChanged: (v) => setState(() => _airMotor = v),
                  ),
                  const SizedBox(height: 12),
                ],

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
            onTap: _resetToDefaults,
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
    final clamped = value.clamp(min, displayMax);
    final label = decimals > 0
        ? '${clamped.toStringAsFixed(decimals)}${unit.isNotEmpty ? ' $unit' : ''}'
        : '${clamped.round()}${unit.isNotEmpty ? ' $unit' : ''}';

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
                Text(label,
                    style: const TextStyle(
                        color: _appTeal,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ],
            ),
            Slider(
              value: clamped,
              min: min,
              max: displayMax,
              divisions: decimals > 0
                  ? ((displayMax - min) * 10).round().clamp(1, 200)
                  : (displayMax - min).round().clamp(1, 200),
              activeColor: _appTeal,
              label: label,
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
              children: List.generate(4, (i) {
                final level = i + 1;
                final selected = _soapDosage == level;
                return GestureDetector(
                  onTap: () => setState(() => _soapDosage = level),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: selected ? _appTeal : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$level',
                      style: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
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
