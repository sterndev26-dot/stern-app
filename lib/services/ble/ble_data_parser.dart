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

  DateTime? getDate(String hexStr, {bool isCalendarDate = false}) {
    try {
      final parts = hexStr.trim().split(' ');
      if (parts.length < 6) return null;

      int seconds, minutes, hours, day, month, year;

      if (isCalendarDate) {
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

  String? parseSoftwareVersion(List<int> bytes) {
    try {
      if (bytes.length < 2) return null;
      return '${bytes[0]}.${bytes[1]}';
    } catch (e) {
      dev.log('parseSoftwareVersion error: $e', name: 'BleDataParser');
      return null;
    }
  }

  // ─────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────

  String bytesToHexString(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  List<int> intToBytes(int value) => value.toString().codeUnits;

  int bytesToInt(List<int> bytes) =>
      int.tryParse(String.fromCharCodes(bytes)) ?? 0;

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
