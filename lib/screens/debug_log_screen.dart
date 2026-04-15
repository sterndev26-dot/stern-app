import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/debug_logger.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  static const _appTeal = Color(0xFF0097A7);
  final _scrollController = ScrollController();
  LogLevel? _filter; // null = show all

  @override
  void initState() {
    super.initState();
    DebugLogger.instance.addListener(_onNewLog);
  }

  @override
  void dispose() {
    DebugLogger.instance.removeListener(_onNewLog);
    _scrollController.dispose();
    super.dispose();
  }

  void _onNewLog() {
    if (!mounted) return;
    setState(() {});
    // Auto-scroll to bottom on new entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<LogEntry> get _filtered {
    final all = DebugLogger.instance.entries;
    if (_filter == null) return all;
    return all.where((e) => e.level == _filter).toList();
  }

  void _copyAll() {
    final text = _filtered
        .map((e) => '[${e.timeStr}][${e.levelStr}][${e.tag}] ${e.message}')
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Log copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: _appTeal,
        foregroundColor: Colors.white,
        title: Text('Debug Log (${entries.length})'),
        actions: [
          // Filter button
          PopupMenuButton<LogLevel?>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All')),
              const PopupMenuItem(value: LogLevel.ble, child: Text('BLE only')),
              const PopupMenuItem(value: LogLevel.error, child: Text('Errors only')),
              const PopupMenuItem(value: LogLevel.warn, child: Text('Warnings only')),
            ],
          ),
          // Copy button
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: 'Copy all',
            onPressed: _copyAll,
          ),
          // Clear button
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            tooltip: 'Clear',
            onPressed: () {
              DebugLogger.instance.clear();
              setState(() {});
            },
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text('No log entries',
                  style: TextStyle(color: Colors.grey, fontSize: 15)),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: entries.length,
              itemBuilder: (_, i) => _LogTile(entry: entries[i]),
            ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final LogEntry entry;
  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            entry.timeStr,
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 10, color: Color(0xFF888888)),
          ),
          const SizedBox(width: 6),
          // Level badge
          Container(
            width: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: entry.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              entry.levelStr,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: entry.color),
            ),
          ),
          const SizedBox(width: 6),
          // Tag + message
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (entry.tag.isNotEmpty)
                  TextSpan(
                    text: '[${entry.tag}] ',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: entry.color,
                        fontWeight: FontWeight.bold),
                  ),
                TextSpan(
                  text: entry.message,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: entry.color == const Color(0xFF424242)
                          ? const Color(0xFFCCCCCC)
                          : entry.color),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
