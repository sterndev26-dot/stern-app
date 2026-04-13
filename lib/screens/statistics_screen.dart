import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
import '../services/ble/ble_data_parser.dart';
import '../services/ble/ble_service.dart';
import '../utils/constants.dart';

class StatisticsScreen extends StatefulWidget {
  final SternProduct product;

  const StatisticsScreen({super.key, required this.product});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  static const _appTeal = Color(0xFF0097A7);

  final _ble = BleService();
  final _parser = BleDataParser();

  bool _isLoading = true;
  bool _isSending = false;
  final List<_StatItem> _stats = [];

  bool get _isSoapType =>
      widget.product.type == SternTypes.soapDispenser ||
      widget.product.type == SternTypes.foamSoapDispenser;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _isLoading = true;
      _stats.clear();
    });

    try {
      // Read main statistics characteristic
      final statsData = await _ble.readCharacteristic(
        BleGattAttributes.uuidStatisticsInfoService,
        BleGattAttributes.uuidStatisticsInfo,
      );

      if (statsData != null && statsData.isNotEmpty) {
        _parseStatsData(statsData);
      }

      // Read scheduled data for hygiene flush (not for soap/foam)
      if (!_isSoapType) {
        await _readScheduledStat(
          'Last Hygiene Flush',
          BleGattAttributes.uuidDataInformationService,
          BleGattAttributes.uuidScheduledCharacteristic,
        );
      }

      // Read filter clean date
      final filterData = await _ble.readCharacteristic(
        BleGattAttributes.uuidDataInformationService,
        BleGattAttributes.uuidInformationRead,
      );
      if (filterData != null && filterData.isNotEmpty) {
        final hexStr = _parser.bytesToHexString(filterData);
        final date = _parser.getDate(hexStr);
        _stats.add(_StatItem(
          label: 'Last Filter Clean',
          value: date != null ? _parser.formatDate(date) : 'No information',
          icon: Icons.filter_alt_outlined,
        ));
      }

      // Add last connected from product
      if (widget.product.lastConnected != null) {
        _stats.add(_StatItem(
          label: 'Last Connected',
          value: widget.product.lastConnected!,
          icon: Icons.bluetooth_connected,
        ));
      }

      // Battery voltage from product record
      if (widget.product.batteryVoltage != null) {
        _stats.add(_StatItem(
          label: 'Battery Voltage',
          value: widget.product.batteryVoltage!,
          icon: Icons.battery_charging_full,
        ));
      }

      // Daily usage
      if (widget.product.dayleUsage != null) {
        _stats.add(_StatItem(
          label: 'Daily Usage',
          value: widget.product.dayleUsage!,
          icon: Icons.water_drop_outlined,
        ));
      }
    } catch (e) {
      dev.log('StatisticsScreen: load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _parseStatsData(List<int> data) {
    // Byte layout matches Android SternProductStatistics:
    // bytes 0-3: time since last powered (little-endian, /10 = seconds)
    // bytes 4-7: number of activations (little-endian)
    // bytes 8-11: total open time (little-endian, /10 = seconds)
    // bytes 12-15: full flush count (little-endian)
    // byte 16: battery state (0=low, 1=medium, 2=ok)

    if (data.length >= 4) {
      final raw = _bytesToUint32LE(data, 0);
      final secs = raw ~/ 10;
      String powered;
      if (secs < 60) {
        powered = '$secs s';
      } else if (secs < 3600) {
        powered = '${secs ~/ 60} min';
      } else {
        powered = '${secs ~/ 3600} h';
      }
      _stats.add(_StatItem(
          label: 'Time Since Powered', value: powered, icon: Icons.power));
    }

    if (data.length >= 8) {
      final activations = _bytesToUint32LE(data, 4);
      _stats.add(_StatItem(
        label: 'Number of Activations',
        value: '$activations',
        icon: Icons.touch_app_outlined,
      ));

      if (data.length >= 12) {
        final totalOpenRaw = _bytesToUint32LE(data, 8);
        final totalSecs = totalOpenRaw ~/ 10;
        final avg = activations > 0 ? totalSecs ~/ activations : 0;
        _stats.add(_StatItem(
          label: 'Avg Open Time',
          value: '$avg s',
          icon: Icons.timer_outlined,
        ));
      }
    }

    if (!_isSoapType && data.length >= 16) {
      final numActivations = _bytesToUint32LE(data, 4);
      final fullFlushCount = _bytesToUint32LE(data, 12);
      final fullPct =
          numActivations > 0 ? (fullFlushCount * 100 ~/ numActivations) : 0;
      final halfPct = numActivations > 0
          ? ((fullFlushCount - numActivations).abs() * 100 ~/
              numActivations)
          : 0;
      _stats.add(_StatItem(
          label: 'Full Flush %', value: '$fullPct%', icon: Icons.water));
      _stats.add(_StatItem(
          label: 'Half Flush %', value: '$halfPct%', icon: Icons.water_outlined));
    }

    if (data.length >= 17) {
      final battByte = data[16];
      final battStr = battByte == 0
          ? 'Low'
          : battByte == 1
              ? 'Medium'
              : battByte == 2
                  ? 'OK'
                  : 'No information';
      _stats.add(_StatItem(
        label: 'Battery State',
        value: battStr,
        icon: Icons.battery_full,
        valueColor: battByte == 0
            ? Colors.red
            : battByte == 1
                ? Colors.orange
                : Colors.green,
      ));
    }
  }

  int _bytesToUint32LE(List<int> data, int offset) {
    if (data.length < offset + 4) return 0;
    return (data[offset] & 0xFF) |
        ((data[offset + 1] & 0xFF) << 8) |
        ((data[offset + 2] & 0xFF) << 16) |
        ((data[offset + 3] & 0xFF) << 24);
  }

  Future<void> _readScheduledStat(
      String label, String svcUuid, String charUuid) async {
    try {
      final data = await _ble.readCharacteristic(svcUuid, charUuid);
      if (data != null && data.isNotEmpty) {
        final hexStr = _parser.bytesToHexString(data);
        final date = _parser.getDate(hexStr);
        _stats.add(_StatItem(
          label: label,
          value: date != null ? _parser.formatDate(date) : 'No information',
          icon: Icons.event_outlined,
        ));
      }
    } catch (e) {
      dev.log('StatisticsScreen: scheduled stat error: $e');
    }
  }

  Future<void> _sendReport() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      // Write a "send report" command via the information write characteristic
      await _ble.writeCharacteristic(
        BleGattAttributes.uuidDataInformationService,
        BleGattAttributes.uuidInformationWrite,
        [0x01],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Report sent'),
              duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send report: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _stats.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bar_chart,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text('No statistics available',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 16)),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _loadStatistics,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: _appTeal),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadStatistics,
                    color: _appTeal,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                      itemCount: _stats.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) => _buildStatCard(_stats[i]),
                    ),
                  ),

        // Send Report FAB
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: _isSending ? null : _sendReport,
            backgroundColor: _appTeal,
            foregroundColor: Colors.white,
            icon: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: const Text('Send Report'),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(_StatItem item) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _appTeal.withValues(alpha: 0.12),
          child: Icon(item.icon, color: _appTeal, size: 20),
        ),
        title: Text(item.label,
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500)),
        trailing: Text(
          item.value,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: item.valueColor ?? Colors.black87),
        ),
      ),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });
}
