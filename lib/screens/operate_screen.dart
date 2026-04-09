import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
import '../models/user.dart';
import '../services/ble/ble_service.dart';
import '../utils/constants.dart';

class OperateScreen extends StatefulWidget {
  final SternProduct product;

  const OperateScreen({super.key, required this.product});

  @override
  State<OperateScreen> createState() => _OperateScreenState();
}

class _OperateScreenState extends State<OperateScreen>
    with SingleTickerProviderStateMixin {
  static const _appBlue = Color(0xFF1A73E8);
  static const int _stepSize = 5;

  late TabController _tabController;
  final _ble = BleService();

  double _hygieneValue = 30;
  double _standbyValue = 30;
  bool _isBusy = false;

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
      if (data != null && data.length >= 2) {
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

  Future<void> _activate() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final duration = _snap(_hygieneValue);
      final success = await _ble.writeCharacteristic(
        BleGattAttributes.uuidDataOperateService,
        BleGattAttributes.uuidOpenCloseValveWrite,
        [duration, 0x01],
      );
      if (mounted) {
        _showSnack(
            success ? 'Activation sent ($duration s)' : 'Failed to activate');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _standby() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final duration = _snap(_standbyValue);
      final success = await _ble.writeCharacteristic(
        BleGattAttributes.uuidDataOperateService,
        BleGattAttributes.uuidOpenCloseValveWrite,
        [duration, 0x02],
      );
      if (mounted) {
        _showSnack(success
            ? 'Standby set ($duration min)'
            : 'Failed to set standby');
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
        labelColor: _appBlue,
        unselectedLabelColor: Colors.grey,
        indicatorColor: _appBlue,
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
          const SizedBox(height: 8),
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
                          color: _appBlue),
                    ),
                  ],
                ),
                Slider(
                  value: _hygieneValue,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  activeColor: _appBlue,
                  label: '${_snap(_hygieneValue)} s',
                  onChanged: (v) => setState(() => _hygieneValue = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isBusy ? null : _activate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _appBlue,
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
                        : Text(
                            _isSoapType ? 'Dispense Now' : 'Activate Now',
                            style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                          color: _appBlue),
                    ),
                  ],
                ),
                Slider(
                  value: _standbyValue,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  activeColor: _appBlue,
                  label: '${_snap(_standbyValue)} min',
                  onChanged: (v) => setState(() => _standbyValue = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isBusy ? null : _standby,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _appBlue,
                      side: const BorderSide(color: _appBlue),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child:
                        const Text('Set Standby', style: TextStyle(fontSize: 16)),
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
                  icon: const Icon(Icons.check, color: _appBlue),
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
                            color: _appBlue),
                        selected: _selectedPreset == name,
                        selectedColor: _appBlue,
                        selectedTileColor: _appBlue.withValues(alpha: 0.08),
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
                    color: Color(0xFF1A73E8))),
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
          foregroundColor: const Color(0xFF1A73E8),
          side: BorderSide(
              color: enabled ? const Color(0xFF1A73E8) : Colors.grey),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label),
      ),
    );
  }
}
