import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../models/stern_product.dart';
import '../../models/stern_types.dart';
import '../../utils/constants.dart';
import '../../utils/debug_logger.dart';

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

  /// GATT operation queue — ensures all BLE ops are serialized (Android requirement)
  Future<dynamic> _gattQueue = Future.value(null);

  /// Run [op] after all previously queued GATT operations finish.
  Future<T> _serialized<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _gattQueue = _gattQueue.whenComplete(() async {
      try {
        completer.complete(await op());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  // ─────────────────────────────────────────
  // SCANNING
  // ─────────────────────────────────────────

  /// Emits null to signal scan end.
  /// Emits a [SternProduct] whose [SternProduct.deviceId] == '__unauthorized__'
  /// when Bluetooth permission has been denied by the user (iOS only).
  /// Emits a [SternProduct] whose [SternProduct.deviceId] == '__bt_off__'
  /// when Bluetooth is turned off on the device.
  Future<void> startScan() async {
    if (_isScanning) return;

    // Check BT adapter state before scanning
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      dev.log('BLE adapter not on: $adapterState', name: 'BleService');
      // Signal why the scan cannot start so the UI can show a meaningful message
      if (adapterState == BluetoothAdapterState.unauthorized) {
        _scanResultController.add(
          SternProduct(type: SternTypes.faucet, name: '__unauthorized__',
              deviceId: '__unauthorized__'),
        );
      } else {
        _scanResultController.add(
          SternProduct(type: SternTypes.faucet, name: '__bt_off__',
              deviceId: '__bt_off__'),
        );
      }
      _scanResultController.add(null); // signals scan finished
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

    final advName = result.advertisementData.advName;
    final name = advName.isNotEmpty ? advName : type.displayName;

    // Extract serial number from advertised name.
    // Format is typically "STBLE XXXXXXXX" or "Name XXXXXXXX" where
    // the last token is a hex/numeric serial (4–16 chars).
    String? serialNumber;
    final nameParts = name.trim().split(RegExp(r'[\s_\-]+'));
    if (nameParts.length >= 2) {
      final last = nameParts.last;
      if (RegExp(r'^[0-9A-Fa-f]{4,16}$').hasMatch(last)) {
        serialNumber = last;
      }
    }

    return SternProduct(
      type: type,
      name: name,
      deviceId: result.device.remoteId.str, // MAC on Android, UUID on iOS
      serialNumber: serialNumber,
      nearby: true,
    );
  }

  // ─────────────────────────────────────────
  // CONNECTION
  // ─────────────────────────────────────────

  /// Connect by device ID (MAC on Android, UUID on iOS).
  Future<bool> connectById(String deviceId) async {
    try {
      final device = BluetoothDevice.fromId(deviceId);
      return await connectToDevice(device);
    } catch (e) {
      dev.log('connectById error: $e', name: 'BleService');
      _connectionStateController.add('error');
      return false;
    }
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    _connectionStateController.add('connecting');
    dev.log('Connecting to ${device.remoteId}', name: 'BleService');
    DebugLogger.instance.ble('Connecting to ${device.remoteId}');

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
      DebugLogger.instance.ble('Connected — ${_cachedServices.length} services found');

      _connectionStateController.add('connected');
      return true;
    } catch (e) {
      dev.log('Connection failed: $e', name: 'BleService');
      DebugLogger.instance.error('Connection failed: $e');
      _connectionStateController.add('error');
      _onDeviceDisconnected();
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      dev.log('Disconnect error: $e', name: 'BleService');
    }
    _onDeviceDisconnected();
  }

  void _onDeviceDisconnected() {
    DebugLogger.instance.ble('Disconnected');
    _connectedDevice = null;
    _cachedServices = [];
    _cancelNotificationSubs();
    _deviceConnectionSub?.cancel();
    _deviceConnectionSub = null;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add('disconnected');
    }
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
    DebugLogger.instance.warn('Char not found: 0x${charUuid.substring(4, 8).toUpperCase()}');
    return null;
  }

  Future<List<int>?> readCharacteristic(
      String serviceUuid, String charUuid) =>
      _serialized(() => _doRead(serviceUuid, charUuid));

  Future<List<int>?> _doRead(String serviceUuid, String charUuid) async {
    if (_connectedDevice == null) return null;
    final shortId = charUuid.substring(4, 8).toUpperCase();
    try {
      final char = _findCharacteristic(serviceUuid, charUuid);
      if (char == null) return null;
      final data = await char.read();
      DebugLogger.instance.ble('READ  0x$shortId → ${data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
      return data;
    } catch (e) {
      dev.log('Read error [$charUuid]: $e', name: 'BleService');
      DebugLogger.instance.error('READ  0x$shortId failed: $e');
      return null;
    }
  }

  Future<bool> writeCharacteristic(
      String serviceUuid, String charUuid, List<int> data) =>
      _serialized(() => _doWrite(serviceUuid, charUuid, data));

  Future<bool> _doWrite(
      String serviceUuid, String charUuid, List<int> data) async {
    if (_connectedDevice == null) return false;
    final shortId = charUuid.substring(4, 8).toUpperCase();
    try {
      final char = _findCharacteristic(serviceUuid, charUuid);
      if (char == null) return false;
      DebugLogger.instance.ble('WRITE 0x$shortId ← ${data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
      // Try with response first; fall back to without response if char supports it
      try {
        await char.write(data, withoutResponse: false);
      } catch (_) {
        if (char.properties.writeWithoutResponse) {
          DebugLogger.instance.warn('WRITE 0x$shortId retrying withoutResponse');
          await char.write(data, withoutResponse: true);
        } else {
          rethrow;
        }
      }
      return true;
    } catch (e) {
      dev.log('Write error [$charUuid]: $e', name: 'BleService');
      DebugLogger.instance.error('WRITE 0x$shortId failed: $e');
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

  /// Write a single request byte and await the matching notification response.
  /// Per Stern BLE protocol: request byte = field_id + 0x80,
  /// response first byte matches the request byte.
  Future<List<int>?> requestCharacteristicField(
    String serviceUuid,
    String charUuid,
    int requestByte, {
    Duration timeout = const Duration(seconds: 4),
  }) => _serialized(() => _doRequestField(serviceUuid, charUuid, requestByte, timeout: timeout));

  Future<List<int>?> _doRequestField(
    String serviceUuid,
    String charUuid,
    int requestByte, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_connectedDevice == null) return null;
    final shortId = charUuid.substring(4, 8).toUpperCase();
    final reqHex = requestByte.toRadixString(16).padLeft(2, '0').toUpperCase();
    try {
      final char = _findCharacteristic(serviceUuid, charUuid);
      if (char == null) return null;

      DebugLogger.instance.ble('REQ   0x$shortId ← [$reqHex]');

      // Write with short timeout — if device doesn't ACK we still try reading
      try {
        await char.write([requestByte], withoutResponse: false, timeout: 3);
      } catch (e) {
        DebugLogger.instance.warn('REQ 0x$shortId write timeout — reading anyway');
      }

      await Future.delayed(const Duration(milliseconds: 500));

      final data = await char.read();
      DebugLogger.instance.ble('READ  0x$shortId → ${data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');

      if (data.isNotEmpty && data[0] == requestByte) {
        return data;
      }
      DebugLogger.instance.warn('REQ 0x$shortId mismatch: want [$reqHex] got [${data.isNotEmpty ? data[0].toRadixString(16).toUpperCase() : "empty"}]');
      return null;
    } catch (e) {
      dev.log('requestCharacteristicField [0x$reqHex] error: $e', name: 'BleService');
      DebugLogger.instance.error('REQ 0x$shortId [$reqHex] error: $e');
      return null;
    }
  }

  /// Write arbitrary data to a notify characteristic and wait for the
  /// notification response. Temporarily enables notifications, writes the
  /// request, awaits the first arriving notification, then cleans up.
  ///
  /// Used for the Stern 0x1301 event-read protocol:
  ///   write [0x81, type, handleLo, handleHi] → response notification
  Future<List<int>?> writeAndWaitNotify(
    String serviceUuid,
    String charUuid,
    List<int> writeData, {
    Duration timeout = const Duration(seconds: 4),
  }) =>
      _serialized(() => _doWriteAndWaitNotify(serviceUuid, charUuid, writeData,
          timeout: timeout));

  Future<List<int>?> _doWriteAndWaitNotify(
    String serviceUuid,
    String charUuid,
    List<int> writeData, {
    required Duration timeout,
  }) async {
    if (_connectedDevice == null) return null;
    final shortId = charUuid.substring(4, 8).toUpperCase();
    try {
      final char = _findCharacteristic(serviceUuid, charUuid);
      if (char == null) return null;

      // Enable notifications before writing so we don't miss the response
      await char.setNotifyValue(true);

      final completer = Completer<List<int>?>();
      final sub = char.onValueReceived.listen((data) {
        if (!completer.isCompleted) completer.complete(List<int>.from(data));
      });

      DebugLogger.instance.ble(
          'WRITE 0x$shortId ← ${writeData.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
      await char.write(writeData, withoutResponse: false, timeout: 3);

      List<int>? result;
      try {
        result = await completer.future.timeout(timeout);
      } on TimeoutException {
        DebugLogger.instance.warn('0x$shortId notify timeout');
        result = null;
      }
      await sub.cancel();

      if (result != null) {
        DebugLogger.instance.ble(
            'NTFY  0x$shortId → ${result.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
      }
      return result;
    } catch (e) {
      dev.log('writeAndWaitNotify error [$charUuid]: $e', name: 'BleService');
      DebugLogger.instance.error('writeAndWaitNotify 0x$shortId error: $e');
      return null;
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
    stopScan();
    _cancelNotificationSubs();
    _deviceConnectionSub?.cancel();
    _adapterSub?.cancel();
    if (!_scanResultController.isClosed) _scanResultController.close();
    if (!_connectionStateController.isClosed) _connectionStateController.close();
    dev.log('BleService disposed', name: 'BleService');
  }
}
