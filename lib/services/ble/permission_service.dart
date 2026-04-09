import 'dart:developer' as dev;
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Handles runtime BLE permissions for iOS and Android.
/// Must be called before any BLE scan or connection attempt.
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// Returns true if all required permissions are granted.
  Future<bool> requestBlePermissions() async {
    if (Platform.isIOS) {
      return _requestIosPermissions();
    } else if (Platform.isAndroid) {
      return _requestAndroidPermissions();
    }
    return true;
  }

  Future<bool> _requestIosPermissions() async {
    final bluetooth = await Permission.bluetooth.request();
    dev.log('iOS bluetooth: $bluetooth', name: 'PermissionService');
    return bluetooth.isGranted;
  }

  Future<bool> _requestAndroidPermissions() async {
    // Android 12+ (API 31+) requires BLUETOOTH_SCAN + BLUETOOTH_CONNECT
    // Android < 12 requires ACCESS_FINE_LOCATION
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final statuses = await permissions.request();
    dev.log('Android permissions: $statuses', name: 'PermissionService');

    final allGranted = statuses.values.every(
      (s) => s.isGranted || s.isLimited,
    );

    return allGranted;
  }

  /// Check without requesting — useful to show UI state
  Future<bool> areBlePermissionsGranted() async {
    if (Platform.isIOS) {
      return (await Permission.bluetooth.status).isGranted;
    }
    final scan = await Permission.bluetoothScan.status;
    final connect = await Permission.bluetoothConnect.status;
    final location = await Permission.locationWhenInUse.status;
    return scan.isGranted && connect.isGranted && location.isGranted;
  }
}
