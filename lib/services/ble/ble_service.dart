import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../models/stern_product.dart';
import '../../models/stern_types.dart';
import '../../utils/constants.dart';

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  final _scanResultController = StreamController<SternProduct?>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  Stream<SternProduct?> get scanResults => _scanResultController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // --- Scanning ---

  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;

    await FlutterBluePlus.stopScan();

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final product = _parseScanResult(result);
        if (product != null) {
          _scanResultController.add(product);
        }
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
    );

    _isScanning = false;
    // Signal scan ended with null
    _scanResultController.add(null);
  }

  Future<void> stopScan() async {
    _isScanning = false;
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  SternProduct? _parseScanResult(ScanResult result) {
    final serviceUuids = result.advertisementData.serviceUuids
        .map((u) => u.str128.toLowerCase())
        .toList();

    SternTypes? type;
    for (final uuid in serviceUuids) {
      if (uuid == BleGattAttributes.sternFaucetUuid) {
        type = SternTypes.faucet;
      } else if (uuid == BleGattAttributes.sternShowerUuid) {
        type = SternTypes.shower;
      } else if (uuid == BleGattAttributes.sternWcUuid) {
        type = SternTypes.wc;
      } else if (uuid == BleGattAttributes.sternUrinalUuid) {
        type = SternTypes.urinal;
      } else if (uuid == BleGattAttributes.sternWaveOnOffUuid) {
        type = SternTypes.waveOnOff;
      } else if (uuid == BleGattAttributes.sternSoapUuid) {
        type = SternTypes.soapDispenser;
      } else if (uuid == BleGattAttributes.sternFoamSoapUuid) {
        type = SternTypes.foamSoapDispenser;
      }
      if (type != null) break;
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

  // --- Connection ---

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;
      _connectionStateController.add(true);
      return true;
    } catch (e) {
      _connectionStateController.add(false);
      return false;
    }
  }

  Future<void> disconnect() async {
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    _connectionStateController.add(false);
  }

  // --- Read / Write characteristics ---

  Future<List<int>?> readCharacteristic(
      String serviceUuid, String charUuid) async {
    if (_connectedDevice == null) return null;
    try {
      final services = await _connectedDevice!.discoverServices();
      for (final service in services) {
        if (service.uuid.str128.toLowerCase() == serviceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            if (char.uuid.str128.toLowerCase() == charUuid.toLowerCase()) {
              return await char.read();
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> writeCharacteristic(
      String serviceUuid, String charUuid, List<int> data) async {
    if (_connectedDevice == null) return false;
    try {
      final services = await _connectedDevice!.discoverServices();
      for (final service in services) {
        if (service.uuid.str128.toLowerCase() == serviceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            if (char.uuid.str128.toLowerCase() == charUuid.toLowerCase()) {
              await char.write(data, withoutResponse: false);
              return true;
            }
          }
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> subscribeToNotifications(
      String serviceUuid,
      String charUuid,
      void Function(List<int> data) onData) async {
    if (_connectedDevice == null) return;
    try {
      final services = await _connectedDevice!.discoverServices();
      for (final service in services) {
        if (service.uuid.str128.toLowerCase() == serviceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            if (char.uuid.str128.toLowerCase() == charUuid.toLowerCase()) {
              await char.setNotifyValue(true);
              char.lastValueStream.listen(onData);
              return;
            }
          }
        }
      }
    } catch (_) {}
  }

  void dispose() {
    stopScan();
    _scanResultController.close();
    _connectionStateController.close();
    _adapterSubscription?.cancel();
  }
}
