import 'dart:developer' as dev;
import 'package:intl/intl.dart';

/// Parses raw BLE byte arrays from Stern devices into readable values.
/// Ported from Android BleDataParser.java
class BleDataParser {
  static final BleDataParser _instance = BleDataParser._internal();
  factory BleDataParser() => _instance;
  BleDataParser._internal();

  // ─────────────────────────────────────
  // DATE PARSING
  // ─────────────────────────────────────

  /// Parses a space-separated hex string into a DateTime.
  /// isCalendarDate=false (default): bytes [1]=sec,[2]=min,[3]=hr,[4]=day,[5]=month,[6]=year
  /// isCalendarDate=true:            bytes [0]=sec,[1]=min,[2]=hr,[3]=day,[4]=month,[5]=year
  /// Returns null if sentinel (255,255,255) detected or parse fails.
  DateTime? getDate(String hexStr, {bool isCalendarDate = false}) {
    try {
      final parts = hexStr.trim().split(' ');

      int seconds, minutes, hours, day, month, year;

      if (isCalendarDate) {
        if (parts.length < 6) return null;
        seconds = int.parse(parts[0], radix: 16);
        minutes = int.parse(parts[1], radix: 16);
        hours   = int.parse(parts[2], radix: 16);
        day     = int.parse(parts[3], radix: 16);
        month   = int.parse(parts[4], radix: 16);
        year    = 2000 + int.parse(parts[5], radix: 16);
      } else {
        if (parts.length < 7) return null;
        seconds = int.parse(parts[1], radix: 16);
        minutes = int.parse(parts[2], radix: 16);
        hours   = int.parse(parts[3], radix: 16);
        day     = int.parse(parts[4], radix: 16);
        month   = int.parse(parts[5], radix: 16);
        year    = 2000 + int.parse(parts[6], radix: 16);
      }

      if (seconds == 255 && minutes == 255 && hours == 255) return null;
      return DateTime(year, month, day, hours, minutes, seconds);
    } catch (e) {
      dev.log('getDate error: $e', name: 'BleDataParser');
      return null;
    }
  }

  String formatDate(DateTime date) =>
      DateFormat('dd MMM, yyyy HH:mm').format(date);

  // ─────────────────────────────────────
  // SERIAL NUMBER
  // ─────────────────────────────────────

  /// Parses serial number: bytes 1-4 reversed → hex string → int.
  /// Returns null for FFFFFFFF (not set).
  String? parseSerialNumber(String hexStr) {
    try {
      final parts = hexStr.trim().split(' ');
      if (parts.length < 5) return null;
      final relevant = parts.sublist(1, 5).reversed.join();
      if (relevant.toUpperCase() == 'FFFFFFFF') return null;
      return int.parse(relevant, radix: 16).toString();
    } catch (e) {
      dev.log('parseSerialNumber error: $e', name: 'BleDataParser');
      return null;
    }
  }

  // ─────────────────────────────────────
  // SOFTWARE VERSION
  // ─────────────────────────────────────

  /// Parses SW version as "major.minor.patch" from hex string.
  /// Android parseSW: hexArr[3].hexArr[2].hexArr[1]
  String? parseSoftwareVersion(String hexStr) {
    try {
      final parts = hexStr.trim().split(' ');
      if (parts.length < 4) return null;
      final patch = int.parse(parts[1], radix: 16);
      final minor = int.parse(parts[2], radix: 16);
      final major = int.parse(parts[3], radix: 16);
      return '$major.$minor.$patch';
    } catch (e) {
      dev.log('parseSoftwareVersion error: $e', name: 'BleDataParser');
      return null;
    }
  }

  // ─────────────────────────────────────
  // PRODUCT NAME
  // ─────────────────────────────────────

  /// Parses device name from hex string (information characteristic).
  /// Android getName: starts at index 1, skips 0xFF/0x00, stops at "$&" terminator.
  String? getName(String hexStr) {
    try {
      final parts = hexStr.trim().split(' ');
      final buffer = StringBuffer();
      for (int i = 1; i < parts.length - 1; i++) {
        final byte = int.parse(parts[i], radix: 16);
        if (byte == 0xFF || byte == 0x00) continue;
        final ch = String.fromCharCode(byte);
        // Check "$&" terminator (two consecutive bytes 0x24 0x26)
        final nextByte = int.parse(parts[i + 1], radix: 16);
        if (byte == 0x24 && nextByte == 0x26) break;
        buffer.write(ch);
      }
      final name = buffer.toString().trim();
      return name.isEmpty ? null : name;
    } catch (e) {
      dev.log('getName error: $e', name: 'BleDataParser');
      return null;
    }
  }

  /// Encodes name for BLE write: [0x01, ...ASCII bytes of "name$&"]
  /// Matches Android stringToASCII(name + "$&")
  List<int> nameToBytes(String name) {
    final ascii = (name + r'$&').codeUnits;
    return [0x01, ...ascii];
  }

  // ─────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────

  String bytesToHexString(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  /// Encode int as 2-byte little-endian (matches Android longToHexArr for val<=0xFFFF)
  List<int> int16ToLEBytes(int value) => [value & 0xFF, (value >> 8) & 0xFF];

  String? parseBatteryVoltage(List<int> bytes) {
    try {
      if (bytes.isEmpty) return null;
      final voltage = bytes[0] / 100.0 + 2.0;
      return '${voltage.toStringAsFixed(2)}V';
    } catch (e) {
      return null;
    }
  }

  String parseValveState(List<int> bytes) {
    if (bytes.isEmpty) return 'Unknown';
    return bytes[0] == 1 ? 'Open' : 'Closed';
  }
}
