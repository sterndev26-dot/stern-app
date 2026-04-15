import 'stern_types.dart';

class SternProduct {
  int? id;
  SternTypes type;
  String name;
  /// On Android this is a MAC address; on iOS this is a Core Bluetooth UUID.
  /// Stored in DB column 'mac_address' for historical reasons.
  String? deviceId;
  String? pairingCode;
  String? lastConnected;
  String? lastUpdate;
  String? batteryVoltage;
  String? swVersion;
  String? serialNumber;
  String? valveState;
  String? dayleUsage;
  String? lastFilterClean;
  bool isPreviouslyConnected;
  bool nearby;

  // In-memory only (not stored in DB)
  bool isRangesReceived;
  bool isScheduledReceived;

  SternProduct({
    this.id,
    required this.type,
    required this.name,
    this.deviceId,
    this.pairingCode,
    this.lastConnected,
    this.lastUpdate,
    this.batteryVoltage,
    this.swVersion,
    this.serialNumber,
    this.valveState,
    this.dayleUsage,
    this.lastFilterClean,
    this.isPreviouslyConnected = false,
    this.nearby = false,
    this.isRangesReceived = false,
    this.isScheduledReceived = false,
  });

  String get imagePath => type.imagePath;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'type': type.toStorageString(),
      'name': name,
      'mac_address': deviceId,   // DB column kept as-is for compatibility
      'pairing_code': pairingCode,
      'last_connected': lastConnected,
      'last_updated': lastUpdate,
      'battery_voltage': batteryVoltage,
      'sw_version': swVersion,
      'serial_number': serialNumber,
      'valve_state': valveState,
      'dayle_usage': dayleUsage,
      'last_filter_clean': lastFilterClean,
      'manifacturing_date': isPreviouslyConnected ? 1 : 0,
      'nearby': nearby ? 1 : 0,
    };
  }

  factory SternProduct.fromMap(Map<String, dynamic> map) {
    return SternProduct(
      id: map['id'] as int?,
      type: SternTypesExtension.fromString(map['type'] as String? ?? ''),
      name: map['name'] as String? ?? '',
      deviceId: map['mac_address'] as String?,
      pairingCode: map['pairing_code'] as String?,
      lastConnected: map['last_connected'] as String?,
      lastUpdate: map['last_updated'] as String?,
      batteryVoltage: map['battery_voltage'] as String?,
      swVersion: map['sw_version'] as String?,
      serialNumber: map['serial_number'] as String?,
      valveState: map['valve_state'] as String?,
      dayleUsage: map['dayle_usage'] as String?,
      lastFilterClean: map['last_filter_clean'] as String?,
      isPreviouslyConnected: (map['manifacturing_date'] as int? ?? 0) == 1,
      nearby: (map['nearby'] as int? ?? 0) == 1,
    );
  }
}
