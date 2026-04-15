import 'package:flutter/material.dart';

enum LogLevel { info, warn, error, ble }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
  });

  String get timeStr {
    final t = time;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }

  Color get color {
    switch (level) {
      case LogLevel.error:
        return const Color(0xFFD32F2F);
      case LogLevel.warn:
        return const Color(0xFFF57C00);
      case LogLevel.ble:
        return const Color(0xFF0097A7);
      case LogLevel.info:
        return const Color(0xFF424242);
    }
  }

  String get levelStr {
    switch (level) {
      case LogLevel.error:
        return 'ERR';
      case LogLevel.warn:
        return 'WRN';
      case LogLevel.ble:
        return 'BLE';
      case LogLevel.info:
        return 'INF';
    }
  }
}

class DebugLogger extends ChangeNotifier {
  static final DebugLogger instance = DebugLogger._();
  DebugLogger._();

  static const _maxEntries = 500;
  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void log(String message, {String tag = '', LogLevel level = LogLevel.info}) {
    _entries.add(LogEntry(
      time: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    ));
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    notifyListeners();
  }

  void ble(String message, {String tag = 'BLE'}) =>
      log(message, tag: tag, level: LogLevel.ble);

  void warn(String message, {String tag = ''}) =>
      log(message, tag: tag, level: LogLevel.warn);

  void error(String message, {String tag = ''}) =>
      log(message, tag: tag, level: LogLevel.error);

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
