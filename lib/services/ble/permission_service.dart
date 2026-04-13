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
  /// If permanently denied, opens app Settings so user can enable manually.
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
    // Android 12+ (API 31+): BLUETOOTH_SCAN + BLUETOOTH_CONNECT
    // All versions: ACCESS_FINE_LOCATION (required for BLE scan results)
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final statuses = await permissions.request();
    dev.log('Android BLE permissions: $statuses', name: 'PermissionService');

    // If any permission is permanently denied, open app settings
    for (final entry in statuses.entries) {
      if (entry.value.isPermanentlyDenied) {
        dev.log('Permission permanently denied: ${entry.key} — opening settings',
            name: 'PermissionService');
        await openAppSettings();
        return false;
      }
    }

    final allGranted = statuses.values.every(
      (s) => s.isGranted || s.isLimited,
    );

    return allGranted;
  }

  /// Check without requesting
  Future<bool> areBlePermissionsGranted() async {
    if (Platform.isIOS) {
      return (await Permission.bluetooth.status).isGranted;
    }
    final scan = await Permission.bluetoothScan.status;
    final connect = await Permission.bluetoothConnect.status;
    final location = await Permission.locationWhenInUse.status;
    return (scan.isGranted || scan.isLimited) &&
        (connect.isGranted || connect.isLimited) &&
        (location.isGranted || location.isLimited);
  }
}
