import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../models/stern_product.dart';
import '../../models/stern_types.dart';
import '../../utils/constants.dart';

/// BLE service singleton — manages scanning, connection, read/write, notifications.
/// Fixes applied:
///   - Service cache (no repeated discoverServices per operation)
///   - Watchdog timer (auto-disconnect if device stops responding)
///   - All stream subscriptions tracked and cancelled on dispose
///   - Error logging via dart:developer
///   - Adapter state check before operations
class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // --- Streams ---
  final _scanResultController = StreamController<SternProduct?>.broadcast();
  final _connectionStateController = StreamController<String>.broadcast();

  Stream<SternProduct?> get scanResults => _scanResultController.stream;
  /// Emits: 'connected' | 'disconnected' | 'connecting' | 'error'
  Stream<String> get connectionState => _connectionStateController.stream;

  // --- State ---
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<BluetoothConnectionState>? _deviceConnectionSub;
  final List<StreamSubscription<List<int>>> _notificationSubs = [];

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  /// Cache of discovered services — avoids repeated discoverServices() calls
  List<BluetoothService> _cachedServices = [];

  /// Watchdog: disconnects if no BLE response within [_watchdogTimeout]
  Timer? _watchdogTimer;
  static const _watchdogTimeout = Duration(seconds: 30);

  // ─────────────────────────────────────────
  // SCANNING
  // ─────────────────────────────────────────

  Future<void> startScan() async {
    if (_isScanning) return;

    // Check BT adapter
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      dev.log('BLE adapter not on: $adapterState', name: 'BleService');
      _scanResultController.add(null);
      return;
    }

    _isScanning = true;
    await FlutterBluePlus.stopScan();

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen(
      (results) {
        for (final r in results) {
          final product = _parseScanResult(r);
          if (product != null) _scanResultController.add(product);
        }
      },
      onError: (e) {
        dev.log('Scan error: $e', name: 'BleService');
        _isScanning = false;
        _scanResultController.add(null);
      },
    );

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      dev.log('startScan failed: $e', name: 'BleService');
    }

    _isScanning = false;
    _scanResultController.add(null); // signals scan finished
    dev.log('Scan finished', name: 'BleService');
  }

  Future<void> stopScan() async {
    _isScanning = false;
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
  }

  SternProduct? _parseScanResult(ScanResult result) {
    final uuids = result.advertisementData.serviceUuids
        .map((u) => u.str128.toLowerCase())
        .toList();

    SternTypes? type;
    for (final uuid in uuids) {
      if (uuid == BleGattAttributes.sternFaucetUuid)        { type = SternTypes.faucet; break; }
      if (uuid == BleGattAttributes.sternShowerUuid)        { type = SternTypes.shower; break; }
      if (uuid == BleGattAttributes.sternWcUuid)            { type = SternTypes.wc; break; }
      if (uuid == BleGattAttributes.sternUrinalUuid)        { type = SternTypes.urinal; break; }
      if (uuid == BleGattAttributes.sternWaveOnOffUuid)     { type = SternTypes.waveOnOff; break; }
      if (uuid == BleGattAttributes.sternSoapUuid)          { type = SternTypes.soapDispenser; break; }
      if (uuid == BleGattAttributes.sternFoamSoapUuid)      { type = SternTypes.foamSoapDispenser; break; }
    }

    if (type == null) return null;

    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : type.displayName;

    return SternProduct(
      type: type,
      name: name,
      macAddress: result.device.remoteId.str,
      nearby: true,
    );
  }

  // ─────────────────────────────────────────
  // CONNECTION
  // ─────────────────────────────────────────

  /// Connect by MAC address — reconstructs BluetoothDevice from ID.
  Future<bool> connectByMac(String macAddress) async {
    try {
      final device = BluetoothDevice.fromId(macAddress);
      return await connectToDevice(device);
    } catch (e) {
      dev.log('connectByMac error: $e', name: 'BleService');
      _connectionStateController.add('error');
      return false;
    }
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    _connectionStateController.add('connecting');
    dev.log('Connecting to ${device.remoteId}', name: 'BleService');

    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;

      // Listen to device disconnect events
      _deviceConnectionSub?.cancel();
      _deviceConnectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          dev.log('Device disconnected', name: 'BleService');
          _onDeviceDisconnected();
        }
      });

      // Discover and cache services once
      _cachedServices = await device.discoverServices();
      dev.log('Discovered ${_cachedServices.length} services', name: 'BleService');

      _startWatchdog();
      _connectionStateController.add('connected');
      return true;
    } catch (e) {
      dev.log('Connection failed: $e', name: 'BleService');
      _connectionStateController.add('error');
      _onDeviceDisconnected();
      return false;
    }
  }

  Future<void> disconnect() async {
    _watchdogTimer?.cancel();
    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      dev.log('Disconnect error: $e', name: 'BleService');
    }
    _onDeviceDisconnected();
  }

  void _onDeviceDisconnected() {
    _connectedDevice = null;
    _cachedServices = [];
    _watchdogTimer?.cancel();
    _cancelNotificationSubs();
    _deviceConnectionSub?.cancel();
    _deviceConnectionSub = null;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add('disconnected');
    }
  }

  // ─────────────────────────────────────────
  // WATCHDOG
  // ─────────────────────────────────────────

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(_watchdogTimeout, () {
      dev.log('Watchdog triggered — device not responding', name: 'BleService');
      disconnect();
    });
  }

  /// Call this every time BLE data is received to reset the watchdog
  void resetWatchdog() {
    if (_connectedDevice != null) _startWatchdog();
  }

  // ─────────────────────────────────────────
  // READ / WRITE (uses cached services)
  // ─────────────────────────────────────────

  BluetoothCharacteristic? _findCharacteristic(
      String serviceUuid, String charUuid) {
    final svcUuid = serviceUuid.toLowerCase();
    final chrUuid = charUuid.toLowerCase();
    for (final service in _cachedServices) {
      if (service.uuid.str128.toLowerCase() == svcUuid) {
        for (final char in service.characteristics) {
          if (char.uuid.str128.toLowerCase() == chrUuid) return char;
        }
      }
    }
    dev.log('Characteristic not found: $charUuid', name: 'BleService');
    return null;
  }

  Future<List<int>?> readCharacteristic(
      String serviceUuid, String charUuid) async {
    if (_connectedDevice == null) return null;
    try {
      final char = _findCharacteristic(serviceUuid, charUuid);
      if (char == null) return null;
      final data = await char.read();
      resetWatchdog();
      return data;
    } catch (e) {
      dev.log('Read error [$charUuid]: $e', name: 'BleService');
      return null;
    }
  }

  Future<bool> writeCharacteristic(
      String serviceUuid, String charUuid, List<int> data) async {
    if (_connectedDevice == null) return false;
    try {
      final char = _findCharacteristic(serviceUuid, charUuid);
      if (char == null) return false;
      await char.write(data, withoutResponse: false);
      resetWatchdog();
      return true;
    } catch (e) {
      dev.log('Write error [$charUuid]: $e', name: 'BleService');
      return false;
    }
  }

  // ─────────────────────────────────────────
  // NOTIFICATIONS (tracked subscriptions + CCCD)
  // ─────────────────────────────────────────

  Future<bool> subscribeToNotifications(
      String serviceUuid,
      String charUuid,
      void Function(List<int> data) onData) async {
    if (_connectedDevice == null) return false;
    try {
      final char = _findCharacteristic(serviceUuid, charUuid);
      if (char == null) return false;

      // Enable CCCD descriptor so device actually sends notifications
      await char.setNotifyValue(true);

      final sub = char.lastValueStream.listen(
        (data) {
          resetWatchdog();
          onData(data);
        },
        onError: (e) => dev.log('Notification error [$charUuid]: $e', name: 'BleService'),
      );

      _notificationSubs.add(sub);
      dev.log('Subscribed to notifications: $charUuid', name: 'BleService');
      return true;
    } catch (e) {
      dev.log('Subscribe error [$charUuid]: $e', name: 'BleService');
      return false;
    }
  }

  void _cancelNotificationSubs() {
    for (final sub in _notificationSubs) {
      sub.cancel();
    }
    _notificationSubs.clear();
  }

  // ─────────────────────────────────────────
  // ADAPTER STATE MONITORING
  // ─────────────────────────────────────────

  void startAdapterMonitoring() {
    _adapterSub?.cancel();
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      dev.log('BT adapter state: $state', name: 'BleService');
      if (state == BluetoothAdapterState.off && _connectedDevice != null) {
        _onDeviceDisconnected();
      }
    });
  }

  // ─────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────

  void dispose() {
    _watchdogTimer?.cancel();
    stopScan();
    _cancelNotificationSubs();
    _deviceConnectionSub?.cancel();
    _adapterSub?.cancel();
    if (!_scanResultController.isClosed) _scanResultController.close();
    if (!_connectionStateController.isClosed) _connectionStateController.close();
    dev.log('BleService disposed', name: 'BleService');
  }
}
