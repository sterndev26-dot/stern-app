import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
import '../models/user.dart';
import '../services/ble/ble_service.dart';
import '../utils/constants.dart';

const _kTeal = Color(0xFF0097A7);

class OperateScreen extends StatefulWidget {
  final SternProduct product;

  const OperateScreen({super.key, required this.product});

  @override
  State<OperateScreen> createState() => _OperateScreenState();
}

class _OperateScreenState extends State<OperateScreen>
    with SingleTickerProviderStateMixin {
  static const int _stepSize = 5;

  late TabController _tabController;
  final _ble = BleService();

  double _hygieneValue = 30;
  double _standbyValue = 30;
  bool _isActivating = false;
  bool _isValveOpen = false;
  bool _isStandbyBusy = false;
  Timer? _valveAutoCloseTimer;

  bool get _isSoapType =>
      widget.product.type == SternTypes.soapDispenser ||
      widget.product.type == SternTypes.foamSoapDispenser;

  bool get _isTechnician => User.instance.isTechnician;

  final List<String> _presets = [];
  String? _selectedPreset;
  bool _newPresetMode = false;
  final _presetNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _isTechnician ? 2 : 1,
      vsync: this,
    );
    _loadCurrentValues();
  }

  @override
  void dispose() {
    _valveAutoCloseTimer?.cancel();
    _tabController.dispose();
    _presetNameController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentValues() async {
    try {
      final data = await _ble.readCharacteristic(
        BleGattAttributes.uuidDataOperateService,
        BleGattAttributes.uuidOperateReadWrite,
      );
      if (data != null && data.length >= 2 && mounted) {
        setState(() {
          _hygieneValue = (data[0] * _stepSize).clamp(0, 100).toDouble();
          _standbyValue = data[1].clamp(0, 100).toDouble();
        });
      }
    } catch (e) {
      dev.log('OperateScreen: load values error: $e');
    }
  }

  int _snap(double val) =>
      ((val / _stepSize).round() * _stepSize).clamp(0, 100);

  // ── Valve open ────────────────────────────────────────────────────────────
  // Android: sends [duration & 0xFF, (duration >> 8) & 0xFF] to
  // UUID_STERN_DATA_OPEN_CLOSE_VALVE_CHARACTIRISTICS_WRITE
  // then auto-closes after (duration*1000 + 2300) ms
  Future<void> _activate() async {
    if (_isActivating) return;

    if (_isValveOpen) {
      // Tap again → close immediately
      await _closeValve();
      return;
    }

    final duration = _snap(_hygieneValue);
    if (duration == 0) {
      _showSnack('Duration cannot be zero');
      return;
    }

    setState(() => _isActivating = true);
    try {
      final success = await _ble.writeCharacteristic(
        BleGattAttributes.uuidDataOperateService,
        BleGattAttributes.uuidOpenCloseValveWrite,
        [duration & 0xFF, (duration >> 8) & 0xFF],
      );

      if (!mounted) return;
      if (success) {
        setState(() {
          _isValveOpen = true;
          _isActivating = false;
        });
        // Auto-close after duration + 2.3 s (matches Android timer)
        _valveAutoCloseTimer?.cancel();
        _valveAutoCloseTimer = Timer(
          Duration(milliseconds: duration * 1000 + 2300),
          () {
            if (mounted) {
              _closeValve();
            }
          },
        );
      } else {
        setState(() => _isActivating = false);
        _showSnack('Failed to activate');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActivating = false);
        _showSnack('Error: $e');
      }
    }
  }

  // ── Valve close ───────────────────────────────────────────────────────────
  // Android closeValve(): sends [0x00, 0x00] to same write characteristic
  Future<void> _closeValve() async {
    _valveAutoCloseTimer?.cancel();
    _valveAutoCloseTimer = null;
    try {
      await _ble.writeCharacteristic(
        BleGattAttributes.uuidDataOperateService,
        BleGattAttributes.uuidOpenCloseValveWrite,
        [0x00, 0x00],
      );
    } catch (e) {
      dev.log('closeValve error: $e');
    } finally {
      if (mounted) setState(() {_isValveOpen = false; _isActivating = false;});
    }
  }

  // ── Standby ───────────────────────────────────────────────────────────────
  // Android sendStandByImidiatlyDuration → sendScheduled(STANDBY_MODE, immediatelyStandBy=true)
  // Builds 14-byte packet:
  //   [0]=writeOrRead=1, [1]=type=3(STANDBY), [2]=duration,
  //   [3]=firstRepeat=0, [4]=secondRepeat=0,
  //   [5]=sec, [6]=min, [7]=hour, [8]=day, [9]=month, [10]=year-2000,
  //   [11-12]=0x00, [13]=handleID=0
  // Written to UUID_STERN_DATA_INFORMATION_SCHEDUALED_CHARACTERISTIC
  Future<void> _standby() async {
    if (_isStandbyBusy) return;

    final duration = _snap(_standbyValue);
    if (duration == 0) {
      _showSnack('Standby duration cannot be zero');
      return;
    }

    setState(() => _isStandbyBusy = true);
    try {
      final now = DateTime.now();
      final packet = List<int>.filled(14, 0);
      packet[0] = 0x01;                      // write
      packet[1] = 0x03;                      // STANDBY_MODE
      packet[2] = duration & 0xFF;           // duration
      packet[3] = 0x00;                      // firstByteRepeat
      packet[4] = 0x00;                      // secondByteRepeat
      packet[5] = now.second & 0xFF;
      packet[6] = now.minute & 0xFF;
      packet[7] = now.hour & 0xFF;
      packet[8] = now.day & 0xFF;
      packet[9] = now.month & 0xFF;
      packet[10] = (now.year - 2000) & 0xFF;
      // [11],[12],[13] = 0x00

      final success = await _ble.writeCharacteristic(
        BleGattAttributes.uuidDataInformationService,
        BleGattAttributes.uuidScheduledCharacteristic,
        packet,
      );

      if (mounted) {
        _showSnack(success
            ? 'Standby set ($duration min)'
            : 'Failed to set standby');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isStandbyBusy = false);
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
    return Column(
      children: [
        if (_isTechnician) _buildTabBar(),
        Expanded(
          child: _isTechnician
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _buildActivateNowTab(),
                    _buildPresetsTab(),
                  ],
                )
              : _buildActivateNowTab(),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: _kTeal,
        unselectedLabelColor: Colors.grey,
        indicatorColor: _kTeal,
        tabs: const [
          Tab(text: 'Activate Now'),
          Tab(text: 'Presets'),
        ],
      ),
    );
  }

  Widget _buildActivateNowTab() {
    final hygieneLabel =
        _isSoapType ? 'Soap Dose Duration' : 'Hygiene Flush Duration';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Product image
          Center(
            child: Image.asset(
              widget.product.imagePath,
              width: 80,
              height: 80,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 16),

          // ── Hygiene / Soap ──────────────────────────
          _SectionCard(
            title: hygieneLabel,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Duration',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 13)),
                    Text(
                      '${_snap(_hygieneValue)} s',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _kTeal),
                    ),
                  ],
                ),
                Slider(
                  value: _hygieneValue,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  activeColor: _kTeal,
                  label: '${_snap(_hygieneValue)} s',
                  onChanged: _isValveOpen
                      ? null
                      : (v) => setState(() => _hygieneValue = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isActivating ? null : _activate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isValveOpen ? Colors.red : _kTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isActivating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(
                            _isValveOpen
                                ? 'Turn Off Now'
                                : (_isSoapType
                                    ? 'Dispense Now'
                                    : 'Activate Now'),
                            style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Standby ─────────────────────────────────
          _SectionCard(
            title: 'Standby Duration',
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Duration',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 13)),
                    Text(
                      '${_snap(_standbyValue)} min',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _kTeal),
                    ),
                  ],
                ),
                Slider(
                  value: _standbyValue,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  activeColor: _kTeal,
                  label: '${_snap(_standbyValue)} min',
                  onChanged: (v) => setState(() => _standbyValue = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isStandbyBusy ? null : _standby,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTeal,
                      side: const BorderSide(color: _kTeal),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isStandbyBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _kTeal))
                        : const Text('Set Standby',
                            style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                  _hygieneValue = 30;
                  _standbyValue = 30;
                  _showSnack('Values reset to default');
                }),
              ),
            ],
          ),
          if (_newPresetMode) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _presetNameController,
              decoration: InputDecoration(
                labelText: 'Preset name',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check, color: _kTeal),
                  onPressed: _savePreset,
                ),
              ),
              onSubmitted: (_) => _savePreset(),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _presets.isEmpty
                ? Center(
                    child: Text('No presets saved yet',
                        style: TextStyle(color: Colors.grey[500])))
                : ListView.builder(
                    itemCount: _presets.length,
                    itemBuilder: (ctx, i) {
                      final name = _presets[i];
                      return ListTile(
                        title: Text(name),
                        leading: const Icon(Icons.bookmark_outline,
                            color: _kTeal),
                        selected: _selectedPreset == name,
                        selectedColor: _kTeal,
                        selectedTileColor: _kTeal.withValues(alpha: 0.08),
                        onTap: () =>
                            setState(() => _selectedPreset = name),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () => setState(() {
                            _presets.removeAt(i);
                            if (_selectedPreset == name) {
                              _selectedPreset = null;
                            }
                          }),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0097A7))),
            const SizedBox(height: 8),
            child,
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
