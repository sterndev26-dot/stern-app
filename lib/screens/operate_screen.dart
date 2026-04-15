import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import '../models/stern_product.dart';
import '../models/stern_types.dart';
import '../services/ble/ble_service.dart';
import '../utils/constants.dart';

const _kTeal = Color(0xFF0097A7);
const _kTealDark = Color(0xFF1A6E7A);

// ══════════════════════════════════════════════════════════════════════════════
// Time slot — a scheduled time with its own duration
// ══════════════════════════════════════════════════════════════════════════════
class _TimeSlot {
  final TimeOfDay time;
  final int duration; // seconds (hygiene) or minutes (standby)
  const _TimeSlot({required this.time, required this.duration});

  _TimeSlot copyWith({TimeOfDay? time, int? duration}) =>
      _TimeSlot(time: time ?? this.time, duration: duration ?? this.duration);
}

// ══════════════════════════════════════════════════════════════════════════════
// Event model — parsed from Characteristic 0x1301 BLE response
// ══════════════════════════════════════════════════════════════════════════════
class _EventModel {
  final int type;          // 2=hygiene flush, 3=standby
  final int duration;      // seconds (hygiene) | minutes (standby)
  final int repeatMinutes; // 0=once, 10080=weekly
  final DateTime dateTime;
  final bool fromLastEvent; // month==99
  final int handle;

  const _EventModel({
    required this.type,
    required this.duration,
    required this.repeatMinutes,
    required this.dateTime,
    required this.fromLastEvent,
    required this.handle,
  });

  bool get isWeekly => repeatMinutes == 7 * 24 * 60;
  bool get isOnce   => repeatMinutes == 0 && !fromLastEvent;

  // 0=Sun..6=Sat
  int get ourWeekday => dateTime.weekday == 7 ? 0 : dateTime.weekday;

  DateTime get nextOccurrence {
    if (fromLastEvent) return DateTime(9999);
    if (isOnce) return dateTime;
    final now = DateTime.now();
    int daysAhead = dateTime.weekday - now.weekday;
    if (daysAhead < 0) daysAhead += 7;
    final candidate = DateTime(
      now.year, now.month, now.day + daysAhead,
      dateTime.hour, dateTime.minute, 0,
    );
    if (daysAhead == 0 && candidate.isBefore(now)) {
      return candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  String get durationStr => type == 2 ? '${duration}s' : '${duration}m';

  String get scheduleStr {
    if (fromLastEvent) {
      final h = repeatMinutes ~/ 60;
      final m = repeatMinutes % 60;
      return 'Auto every ${h > 0 ? '${h}h ' : ''}${m > 0 ? '${m}m' : ''}';
    }
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final t = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    if (isWeekly) return '${days[ourWeekday]}  $t';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}  $t';
  }

  String get repeatStr {
    if (fromLastEvent) return 'Auto';
    if (isWeekly) return 'Weekly';
    return 'Once';
  }

  static _EventModel? fromBleResponse(List<int> data) {
    if (data.length < 13 || data[0] != 0x81) return null;
    final type        = data[1];
    final duration    = data[2];
    final repeatMin   = data[3] | (data[4] << 8);
    final sec         = data[5];
    final min         = data[6];
    final hour        = data[7];
    final day         = data[8];
    final month       = data[9];
    final year        = data[10] + 2000;
    final handle      = data[11] | (data[12] << 8);
    final fromLast    = month == 99;
    final dt = fromLast
        ? DateTime(2000, 1, 1, hour, min, sec)
        : DateTime(year, month.clamp(1, 12), day.clamp(1, 28), hour, min, sec);
    return _EventModel(
      type: type, duration: duration, repeatMinutes: repeatMin,
      dateTime: dt, fromLastEvent: fromLast, handle: handle,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OperateScreen
// ══════════════════════════════════════════════════════════════════════════════
class OperateScreen extends StatefulWidget {
  final SternProduct product;
  const OperateScreen({super.key, required this.product});

  @override
  State<OperateScreen> createState() => _OperateScreenState();
}

class _OperateScreenState extends State<OperateScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _ble = BleService();

  // ── Tab 1 ──────────────────────────────────────────────────────────────────
  double _activateDuration = 0;
  double _lockoutDuration  = 1;
  bool   _isActivating     = false;
  bool   _isValveOpen      = false;
  bool   _isLockoutBusy    = false;
  Timer? _valveAutoCloseTimer;

  // ── Tab 2: Schedule Hygiene Flush ──────────────────────────────────────────
  double _hygieneInterval       = 1;
  double _hygieneFlushDuration  = 30;
  bool   _hygieneFromLastUse    = false;
  bool   _hygieneActivationBusy = false;

  // day (0=Sun..6=Sat) → list of up to 2 TimeSlots
  final Map<int, List<_TimeSlot>> _hygieneSlots = {};

  DateTime?   _hygieneSetByDate;
  _TimeSlot?  _hygieneSetByDateSlot;

  bool   _hygieneApplyBusy = false;

  List<_EventModel> _hygieneEvents  = [];
  bool              _hygieneLoading = false;

  // ── Tab 3: Schedule Standby ────────────────────────────────────────────────
  // day (0=Sun..6=Sat) → list of up to 2 TimeSlots
  final Map<int, List<_TimeSlot>> _standbySlots = {};

  DateTime?   _standbySetByDate;
  _TimeSlot?  _standbySetByDateSlot;

  bool   _standbyApplyBusy = false;

  List<_EventModel> _standbyEvents  = [];
  bool              _standbyLoading = false;

  bool get _isSoapType =>
      widget.product.type == SternTypes.soapDispenser ||
      widget.product.type == SternTypes.foamSoapDispenser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return; // wait for animation to settle
    if (_tabController.index == 1) _loadHygieneEvents();
    if (_tabController.index == 2) _loadStandbyEvents();
  }

  @override
  void dispose() {
    _valveAutoCloseTimer?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BLE actions
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _activate() async {
    if (_isActivating) return;
    if (_isValveOpen) { await _closeValve(); return; }
    final dur = _activateDuration.round();
    if (dur == 0) { _showSnack('Set a duration first'); return; }
    setState(() => _isActivating = true);
    try {
      final ok = await _ble.writeCharacteristic(
        BleGattAttributes.uuidDataOperateService,
        BleGattAttributes.uuidOpenCloseValveWrite,
        [dur & 0xFF, (dur >> 8) & 0xFF],
      );
      if (!mounted) return;
      if (ok) {
        setState(() { _isValveOpen = true; _isActivating = false; });
        _valveAutoCloseTimer?.cancel();
        _valveAutoCloseTimer = Timer(
          Duration(milliseconds: dur * 1000 + 2300),
          () { if (mounted) _closeValve(); },
        );
      } else {
        setState(() => _isActivating = false);
        _showSnack('Activation failed');
      }
    } catch (e) {
      if (mounted) { setState(() => _isActivating = false); _showSnack('Error: $e'); }
    }
  }

  Future<void> _closeValve() async {
    _valveAutoCloseTimer?.cancel();
    _valveAutoCloseTimer = null;
    try {
      await _ble.writeCharacteristic(
        BleGattAttributes.uuidDataOperateService,
        BleGattAttributes.uuidOpenCloseValveWrite,
        [0x00, 0x00],
      );
    } catch (e) { dev.log('closeValve: $e'); }
    finally {
      if (mounted) setState(() { _isValveOpen = false; _isActivating = false; });
    }
  }

  Future<void> _setLockout() async {
    if (_isLockoutBusy) return;
    setState(() => _isLockoutBusy = true);
    try {
      final ok = await _ble.writeCharacteristic(
        BleGattAttributes.uuidDataInformationService,
        BleGattAttributes.uuidScheduledCharacteristic,
        _buildEventPacket(type: 0x03, duration: _lockoutDuration.round(),
            repeatMinutes: 0, date: DateTime.now(), fromLastEvent: false),
      );
      if (mounted) _showSnack(ok ? 'Lockout set (${_lockoutDuration.round()} min)' : 'Failed');
    } catch (e) { if (mounted) _showSnack('Error: $e'); }
    finally { if (mounted) setState(() => _isLockoutBusy = false); }
  }

  Future<void> _setHygieneActivation() async {
    if (_hygieneActivationBusy) return;
    setState(() => _hygieneActivationBusy = true);
    try {
      final ok = await _ble.writeCharacteristic(
        BleGattAttributes.uuidDataInformationService,
        BleGattAttributes.uuidScheduledCharacteristic,
        _buildEventPacket(
          type: 0x02,
          duration: _hygieneFlushDuration.round(),
          repeatMinutes: (_hygieneInterval * 60).round(),
          date: DateTime.now(),
          fromLastEvent: _hygieneFromLastUse,
        ),
      );
      if (mounted) {
        _showSnack(ok ? 'Hygiene flush activation set' : 'Failed');
        if (ok) _loadHygieneEvents();
      }
    } catch (e) { if (mounted) _showSnack('Error: $e'); }
    finally { if (mounted) setState(() => _hygieneActivationBusy = false); }
  }

  Future<void> _applyHygieneSchedule() async {
    if (_hygieneApplyBusy) return;

    if (_hygieneSetByDate != null) {
      if (_hygieneSetByDateSlot == null) { _showSnack('Set a time first'); return; }
      setState(() => _hygieneApplyBusy = true);
      try {
        final slot = _hygieneSetByDateSlot!;
        final d = _hygieneSetByDate!;
        final schedDate = DateTime(d.year, d.month, d.day, slot.time.hour, slot.time.minute, 0);
        final ok = await _ble.writeCharacteristic(
          BleGattAttributes.uuidDataInformationService,
          BleGattAttributes.uuidScheduledCharacteristic,
          _buildEventPacket(type: 0x02, duration: slot.duration,
              repeatMinutes: 0, date: schedDate, fromLastEvent: false),
        );
        if (mounted) { _showSnack(ok ? 'Schedule applied' : 'Failed'); if (ok) _loadHygieneEvents(); }
      } catch (e) { if (mounted) _showSnack('Error: $e'); }
      finally { if (mounted) setState(() => _hygieneApplyBusy = false); }
      return;
    }

    if (_hygieneSlots.isEmpty) { _showSnack('Select at least one day'); return; }
    setState(() => _hygieneApplyBusy = true);
    try {
      int sent = 0;
      for (final entry in _hygieneSlots.entries) {
        final base = _nextWeekdayDate(entry.key);
        for (final slot in entry.value) {
          final schedDate = DateTime(base.year, base.month, base.day,
              slot.time.hour, slot.time.minute, 0);
          final ok = await _ble.writeCharacteristic(
            BleGattAttributes.uuidDataInformationService,
            BleGattAttributes.uuidScheduledCharacteristic,
            _buildEventPacket(type: 0x02, duration: slot.duration,
                repeatMinutes: 7 * 24 * 60, date: schedDate, fromLastEvent: false),
          );
          if (ok) sent++;
        }
      }
      if (mounted) {
        _showSnack(sent > 0 ? 'Applied $sent schedule(s)' : 'Failed');
        if (sent > 0) _loadHygieneEvents();
      }
    } catch (e) { if (mounted) _showSnack('Error: $e'); }
    finally { if (mounted) setState(() => _hygieneApplyBusy = false); }
  }

  Future<void> _applyStandbySchedule() async {
    if (_standbyApplyBusy) return;

    if (_standbySetByDate != null) {
      if (_standbySetByDateSlot == null) { _showSnack('Set a time first'); return; }
      setState(() => _standbyApplyBusy = true);
      try {
        final slot = _standbySetByDateSlot!;
        final d = _standbySetByDate!;
        final schedDate = DateTime(d.year, d.month, d.day, slot.time.hour, slot.time.minute, 0);
        final ok = await _ble.writeCharacteristic(
          BleGattAttributes.uuidDataInformationService,
          BleGattAttributes.uuidScheduledCharacteristic,
          _buildEventPacket(type: 0x03, duration: slot.duration,
              repeatMinutes: 0, date: schedDate, fromLastEvent: false),
        );
        if (mounted) { _showSnack(ok ? 'Schedule applied' : 'Failed'); if (ok) _loadStandbyEvents(); }
      } catch (e) { if (mounted) _showSnack('Error: $e'); }
      finally { if (mounted) setState(() => _standbyApplyBusy = false); }
      return;
    }

    if (_standbySlots.isEmpty) { _showSnack('Select at least one day'); return; }
    setState(() => _standbyApplyBusy = true);
    try {
      int sent = 0;
      for (final entry in _standbySlots.entries) {
        final base = _nextWeekdayDate(entry.key);
        for (final slot in entry.value) {
          final schedDate = DateTime(base.year, base.month, base.day,
              slot.time.hour, slot.time.minute, 0);
          final ok = await _ble.writeCharacteristic(
            BleGattAttributes.uuidDataInformationService,
            BleGattAttributes.uuidScheduledCharacteristic,
            _buildEventPacket(type: 0x03, duration: slot.duration,
                repeatMinutes: 7 * 24 * 60, date: schedDate, fromLastEvent: false),
          );
          if (ok) sent++;
        }
      }
      if (mounted) {
        _showSnack(sent > 0 ? 'Applied $sent schedule(s)' : 'Failed');
        if (sent > 0) _loadStandbyEvents();
      }
    } catch (e) { if (mounted) _showSnack('Error: $e'); }
    finally { if (mounted) setState(() => _standbyApplyBusy = false); }
  }

  // ── Day / time selection ───────────────────────────────────────────────────

  void _onHygieneDayTapped(int day) => _manageDaySlots(day, isSeconds: true);
  void _onStandbyDayTapped(int day) => _manageDaySlots(day, isSeconds: false);

  /// Tap a day button:
  ///   • 0 slots → directly open picker to add first slot
  ///   • 1–2 slots → show dialog to add (up to 2) or remove existing slots
  Future<void> _manageDaySlots(int day, {required bool isSeconds}) async {
    final map      = isSeconds ? _hygieneSlots : _standbySlots;
    final existing = List<_TimeSlot>.from(map[day] ?? []);

    if (existing.isEmpty) {
      // Fast path: directly add
      final slot = await _pickTimeSlot(isSeconds: isSeconds);
      if (!mounted || slot == null) return;
      setState(() {
        if (isSeconds) { _hygieneSetByDate = null; _hygieneSetByDateSlot = null; }
        else            { _standbySetByDate = null; _standbySetByDateSlot = null; }
        map[day] = [slot];
      });
      return;
    }

    // Show manage dialog
    const dayNames = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    final unit = isSeconds ? 'sec' : 'min';
    // working copy mutated inside StatefulBuilder
    final working = List<_TimeSlot>.from(existing);
    bool addNew   = false;
    bool saved    = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(dayNames[day]),
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < working.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule, color: _kTeal, size: 20),
                  title: Text(_fmtSlot(working[i], unit)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: Colors.red, size: 20),
                    onPressed: () => setLocal(() => working.removeAt(i)),
                  ),
                ),
              if (working.length < 2)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_circle_outline, color: _kTeal, size: 20),
                  title: const Text('Add time', style: TextStyle(color: _kTeal)),
                  onTap: () { addNew = true; Navigator.pop(ctx); },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: _kTeal),
              onPressed: () { saved = true; Navigator.pop(ctx); },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (addNew) {
      // "Add time" also saves current working list, then appends new slot
      final slot = await _pickTimeSlot(isSeconds: isSeconds);
      if (!mounted) return;
      if (slot != null) working.add(slot);
      saved = true;
    }

    if (!saved) return;
    setState(() {
      if (isSeconds) { _hygieneSetByDate = null; _hygieneSetByDateSlot = null; }
      else            { _standbySetByDate = null; _standbySetByDateSlot = null; }
      if (working.isEmpty) { map.remove(day); }
      else { map[day] = working; }
    });
  }

  // ── Date picker ────────────────────────────────────────────────────────────

  Future<void> _pickHygieneDate() async {
    final d = await _showDatePicker();
    if (d == null || !mounted) return;
    setState(() {
      _hygieneSetByDate     = d;
      _hygieneSetByDateSlot = null;
      _hygieneSlots.clear(); // mutually exclusive with weekly selection
    });
    final slot = await _pickTimeSlot(isSeconds: true);
    if (mounted) setState(() => _hygieneSetByDateSlot = slot);
  }

  Future<void> _pickStandbyDate() async {
    final d = await _showDatePicker();
    if (d == null || !mounted) return;
    setState(() {
      _standbySetByDate     = d;
      _standbySetByDateSlot = null;
      _standbySlots.clear();
    });
    final slot = await _pickTimeSlot(isSeconds: false);
    if (mounted) setState(() => _standbySetByDateSlot = slot);
  }

  // ── Load events from device ────────────────────────────────────────────────

  Future<void> _loadHygieneEvents() async {
    if (_hygieneLoading) return;
    setState(() => _hygieneLoading = true);
    final ev = await _loadEventsFromDevice(0x02);
    if (mounted) setState(() { _hygieneEvents = ev; _hygieneLoading = false; });
  }

  Future<void> _loadStandbyEvents() async {
    if (_standbyLoading) return;
    setState(() => _standbyLoading = true);
    final ev = await _loadEventsFromDevice(0x03);
    if (mounted) setState(() { _standbyEvents = ev; _standbyLoading = false; });
  }

  Future<void> _deleteEvent(_EventModel event, {required bool isHygiene}) async {
    final handle = event.handle;
    final ok = await _ble.writeCharacteristic(
      BleGattAttributes.uuidDataInformationService,
      BleGattAttributes.uuidScheduledCharacteristic,
      [0x02, 0x00, handle & 0xFF, (handle >> 8) & 0xFF],
    );
    if (!mounted) return;
    if (ok) {
      if (isHygiene) {
        setState(() => _hygieneEvents.removeWhere((e) => e.handle == handle));
      } else {
        setState(() => _standbyEvents.removeWhere((e) => e.handle == handle));
      }
      _showSnack('Schedule deleted');
    } else {
      _showSnack('Delete failed');
        // Re-add removed tile if swipe-dismissed but write failed
      if (isHygiene) {
        _loadHygieneEvents();
      } else {
        _loadStandbyEvents();
      }
    }
  }

  Future<List<_EventModel>> _loadEventsFromDevice(int type) async {
    final result = <_EventModel>[];
    int handle = 0;
    try {
      for (var i = 0; i < 100; i++) {
        final resp = await _ble.writeAndWaitNotify(
          BleGattAttributes.uuidDataInformationService,
          BleGattAttributes.uuidScheduledCharacteristic,
          [0x81, type, handle & 0xFF, (handle >> 8) & 0xFF],
        );
        if (resp == null || resp.length < 13 || resp[0] != 0x81) break;
        final returnedHandle = resp[11] | (resp[12] << 8);
        if (returnedHandle == 0) break;
        final ev = _EventModel.fromBleResponse(resp);
        if (ev != null) result.add(ev);
        handle = returnedHandle;
      }
    } catch (e) { dev.log('loadEvents: $e'); }
    result.sort((a, b) => a.nextOccurrence.compareTo(b.nextOccurrence));
    return result;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Helpers
  // ════════════════════════════════════════════════════════════════════════════

  List<int> _buildEventPacket({
    required int type, required int duration,
    required int repeatMinutes, required DateTime date,
    required bool fromLastEvent,
  }) {
    final p = List<int>.filled(14, 0);
    p[0]  = 0x01;
    p[1]  = type;
    p[2]  = duration & 0xFF;
    p[3]  = repeatMinutes & 0xFF;
    p[4]  = (repeatMinutes >> 8) & 0xFF;
    p[5]  = date.second & 0xFF;
    p[6]  = date.minute & 0xFF;
    p[7]  = date.hour & 0xFF;
    p[8]  = date.day & 0xFF;
    p[9]  = fromLastEvent ? 99 : (date.month & 0xFF);
    p[10] = (date.year - 2000) & 0xFF;
    return p;
  }

  DateTime _nextWeekdayDate(int weekday) {
    final now = DateTime.now();
    final dartTarget = weekday == 0 ? 7 : weekday;
    int ahead = dartTarget - now.weekday;
    if (ahead <= 0) ahead += 7;
    return DateTime(now.year, now.month, now.day + ahead, 0, 0, 0);
  }

  /// Shows time picker then duration picker. Returns a [_TimeSlot] or null.
  /// [isSeconds]: true for hygiene (sec), false for standby (min).
  Future<_TimeSlot?> _pickTimeSlot({required bool isSeconds}) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: _kTeal)),
        child: child!,
      ),
    );
    if (time == null || !mounted) return null;

    final duration = await _showDurationPicker(
      initialValue: isSeconds ? 30 : 3,
      min: isSeconds ? 5 : 1,
      max: isSeconds ? 120 : 60,
      unit: isSeconds ? 'sec' : 'min',
      stepSize: isSeconds ? 5 : 1,
    );
    if (duration == null || !mounted) return null;

    return _TimeSlot(time: time, duration: duration);
  }

  /// Shows a dialog with a slider to pick a duration. Returns the chosen value
  /// or null if dismissed.
  Future<int?> _showDurationPicker({
    required int initialValue,
    required int min,
    required int max,
    required String unit,
    required int stepSize,
  }) async {
    int current = initialValue;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Set Duration'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 80,
                decoration: BoxDecoration(
                    border: Border.all(color: _kTeal, width: 1.5),
                    borderRadius: BorderRadius.circular(4)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('$current',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Text(unit, style: const TextStyle(fontSize: 16)),
            ]),
            const SizedBox(height: 8),
            Slider(
              value: current.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: (max - min) ~/ stepSize,
              activeColor: _kTeal,
              onChanged: (v) =>
                  setLocal(() => current = ((v / stepSize).round() * stepSize)
                      .clamp(min, max)),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, current),
              style: TextButton.styleFrom(foregroundColor: _kTeal),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _showDatePicker() async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: _kTeal)),
        child: child!,
      ),
    );
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
  );

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtSlot(_TimeSlot s, String unit) {
    final h = s.time.hour.toString().padLeft(2, '0');
    final m = s.time.minute.toString().padLeft(2, '0');
    return '$h:$m · ${s.duration}$unit';
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Build
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildActivateNowTab(),
              _buildScheduleHygieneTab(),
              _buildScheduleStandbyTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() => Container(
    color: Colors.white,
    child: TabBar(
      controller: _tabController,
      labelColor: _kTeal,
      unselectedLabelColor: Colors.grey[500],
      indicatorColor: _kTeal,
      indicatorWeight: 2.5,
      labelStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
      unselectedLabelStyle: const TextStyle(fontSize: 10.5),
      tabs: const [
        Tab(text: 'ACTIVATE\nNOW',           height: 44),
        Tab(text: 'SCHEDULE\nHYGIENE FL...', height: 44),
        Tab(text: 'SCHEDULE\nSTANDBY',       height: 44),
      ],
    ),
  );

  // ── Tab 1 ─────────────────────────────────────────────────────────────────
  Widget _buildActivateNowTab() {
    final title = _isSoapType ? 'Manual Priming/Dispensing' : 'Manual Priming/Activation';
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _ValueRow(value: _activateDuration.round(), unit: 'sec'),
        Slider(value: _activateDuration, min: 0, max: 100, divisions: 20,
            activeColor: _kTeal,
            onChanged: _isValveOpen ? null
                : (v) => setState(() => _activateDuration = (v / 5).round() * 5.0)),
        const SizedBox(height: 8),
        _TealOutlineButton(
            label: _isValveOpen ? 'Turn Off Now' : 'Activate',
            busy: _isActivating, onTap: _activate),
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 20),
        const Text('Set Lock Out Time', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _ValueRow(value: _lockoutDuration.round(), unit: 'min'),
        Slider(value: _lockoutDuration, min: 1, max: 60, divisions: 59,
            activeColor: _kTeal,
            onChanged: (v) => setState(() => _lockoutDuration = v.roundToDouble())),
        const SizedBox(height: 8),
        _TealOutlineButton(label: 'Activate', busy: _isLockoutBusy, onTap: _setLockout),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ── Tab 2 ─────────────────────────────────────────────────────────────────
  Widget _buildScheduleHygieneTab() {
    final activeDate = _hygieneSetByDate;
    final dateSlot   = _hygieneSetByDateSlot;
    String dateLabel = 'Set by Date';
    if (activeDate != null) {
      dateLabel = _fmtDate(activeDate);
      if (dateSlot != null) dateLabel += '  ${_fmtSlot(dateSlot, 'sec')}';
    }

    return Column(children: [
      const _PresetBar(),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── Hygiene Flush Activation ──
          const Text('Hygiene Flush Activation', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _LabeledValueRow(label: 'Interval', value: _hygieneInterval.round(), unit: 'hour'),
          Slider(value: _hygieneInterval, min: 1, max: 24, divisions: 23, activeColor: _kTeal,
              onChanged: (v) => setState(() => _hygieneInterval = v.roundToDouble())),
          const SizedBox(height: 4),
          _LabeledValueRow(label: 'Flush duration',
              value: _hygieneFlushDuration.round(), unit: 'sec'),
          Slider(value: _hygieneFlushDuration, min: 5, max: 120, divisions: 23,
              activeColor: _kTeal,
              onChanged: (v) => setState(
                  () => _hygieneFlushDuration = (v / 5).round() * 5.0)),
          Row(children: [
            Checkbox(value: _hygieneFromLastUse, activeColor: _kTeal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                onChanged: (v) => setState(() => _hygieneFromLastUse = v ?? false)),
            const Text('From last use', style: TextStyle(fontSize: 15)),
          ]),
          const SizedBox(height: 8),
          _TealOutlineButton(label: 'Set', busy: _hygieneActivationBusy,
              onTap: _setHygieneActivation),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // ── Set To Weekly Schedule ──
          const Text('Set To Weekly Schedule', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _DaySelector(
            slots: _hygieneSlots,
            onSelect: _onHygieneDayTapped,
          ),
          if (_hygieneSlots.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PendingSlotsList(slots: _hygieneSlots, unit: 'sec',
                onRemove: (day, i) => setState(() {
                  _hygieneSlots[day]!.removeAt(i);
                  if (_hygieneSlots[day]!.isEmpty) _hygieneSlots.remove(day);
                })),
          ],
          const SizedBox(height: 10),

          _TealOutlineButton(label: dateLabel, busy: false, onTap: _pickHygieneDate),

          const SizedBox(height: 16),
          _TealOutlineButton(label: 'Apply', busy: _hygieneApplyBusy,
              onTap: _applyHygieneSchedule),
          const SizedBox(height: 20),
          _EventsList(events: _hygieneEvents, loading: _hygieneLoading,
              filterDay: null,
              onDelete: (e) => _deleteEvent(e, isHygiene: true)),
          const SizedBox(height: 16),
        ]),
      )),
    ]);
  }

  // ── Tab 3 ─────────────────────────────────────────────────────────────────
  Widget _buildScheduleStandbyTab() {
    final activeDate  = _standbySetByDate;
    final dateSlot    = _standbySetByDateSlot;
    String dateLabel  = 'Set by Date';
    if (activeDate != null) {
      dateLabel = _fmtDate(activeDate);
      if (dateSlot != null) dateLabel += '  ${_fmtSlot(dateSlot, 'min')}';
    }

    return Column(children: [
      const _PresetBar(),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Set To Weekly Schedule', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _DaySelector(
            slots: _standbySlots,
            onSelect: _onStandbyDayTapped,
          ),
          if (_standbySlots.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PendingSlotsList(slots: _standbySlots, unit: 'min',
                onRemove: (day, i) => setState(() {
                  _standbySlots[day]!.removeAt(i);
                  if (_standbySlots[day]!.isEmpty) _standbySlots.remove(day);
                })),
          ],
          const SizedBox(height: 10),

          _TealOutlineButton(label: dateLabel, busy: false, onTap: _pickStandbyDate),

          const SizedBox(height: 16),
          _TealOutlineButton(label: 'Apply', busy: _standbyApplyBusy,
              onTap: _applyStandbySchedule),
          const SizedBox(height: 20),
          _EventsList(events: _standbyEvents, loading: _standbyLoading,
              filterDay: null,
              onDelete: (e) => _deleteEvent(e, isHygiene: false)),
          const SizedBox(height: 16),
        ]),
      )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ══════════════════════════════════════════════════════════════════════════════

class _ValueRow extends StatelessWidget {
  final int value; final String unit;
  const _ValueRow({required this.value, required this.unit});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 100,
        decoration: BoxDecoration(
            border: Border.all(color: _kTeal, width: 1.5),
            borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text('$value', textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500)),
      ),
      const SizedBox(width: 10),
      Text(unit, style: const TextStyle(fontSize: 16)),
    ],
  );
}

class _LabeledValueRow extends StatelessWidget {
  final String label; final int value; final String unit;
  const _LabeledValueRow(
      {required this.label, required this.value, required this.unit});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(label, style: TextStyle(fontSize: 15, color: Colors.grey[700])),
    const Spacer(),
    Container(
      width: 70,
      decoration: BoxDecoration(
          border: Border.all(color: _kTeal, width: 1.5),
          borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text('$value', textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
    ),
    const SizedBox(width: 8),
    SizedBox(width: 36, child: Text(unit, style: const TextStyle(fontSize: 15))),
  ]);
}

class _TealOutlineButton extends StatelessWidget {
  final String label; final bool busy; final VoidCallback onTap;
  const _TealOutlineButton(
      {required this.label, required this.busy, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _kTeal,
        side: BorderSide(color: busy ? Colors.grey[300]! : _kTeal, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: busy
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kTeal))
          : Text(label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
    ),
  );
}

class _PresetBar extends StatelessWidget {
  const _PresetBar();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: Row(children: [
      _PresetBtn(label: 'New Preset',  enabled: true,  onTap: () {}),
      const SizedBox(width: 6),
      _PresetBtn(label: 'Load Preset', enabled: true,  onTap: () {}),
      const SizedBox(width: 6),
      _PresetBtn(label: 'Save Preset', enabled: false, onTap: () {}),
    ]),
  );
}

class _PresetBtn extends StatelessWidget {
  final String label; final bool enabled; final VoidCallback onTap;
  const _PresetBtn({required this.label, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: enabled ? _kTeal : Colors.grey[400],
        side: BorderSide(color: enabled ? _kTeal : Colors.grey[300]!, width: 1.2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: FittedBox(
        child: Text(label,
            style: TextStyle(fontSize: 13,
                color: enabled ? _kTeal : Colors.grey[400])),
      ),
    ),
  );
}

class _DaySelector extends StatelessWidget {
  /// day (0=Sun..6=Sat) → list of up to 2 scheduled TimeSlots
  final Map<int, List<_TimeSlot>> slots;
  final void Function(int) onSelect;
  const _DaySelector({required this.slots, required this.onSelect});
  static const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(7, (i) {
      final hasSlots = (slots[i] ?? []).isNotEmpty;
      return Expanded(
        child: GestureDetector(
          onTap: () => onSelect(i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: hasSlots ? _kTeal : _kTealDark,
            ),
            child: Text(_days[i],
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: hasSlots ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }),
  );
}

class _EventsList extends StatelessWidget {
  final List<_EventModel> events;
  final bool loading;
  final int? filterDay;
  final void Function(_EventModel) onDelete;
  const _EventsList({required this.events, required this.loading,
      required this.filterDay, required this.onDelete});

  List<_EventModel> get _filtered {
    if (filterDay == null) {
      final upcoming = events.where((e) => !e.fromLastEvent).toList()
        ..sort((a, b) => a.nextOccurrence.compareTo(b.nextOccurrence));
      final auto = events.where((e) => e.fromLastEvent).toList();
      return [...(upcoming.isNotEmpty ? [upcoming.first] : []), ...auto];
    }
    return events.where((e) {
      if (e.fromLastEvent) return true;
      if (e.isWeekly) return e.ourWeekday == filterDay;
      return e.nextOccurrence.weekday == (filterDay == 0 ? 7 : filterDay!);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filtered;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Text('Upcoming Events',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const Spacer(),
        if (loading)
          const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kTeal)),
      ]),
      const SizedBox(height: 6),
      if (!loading && shown.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No scheduled events', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14)))
      else
        ...shown.map((e) => Dismissible(
          key: ValueKey(e.handle),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Colors.red[400],
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
          ),
          onDismissed: (_) => onDelete(e),
          child: _EventTile(event: e),
        )),
    ]);
  }
}

// Shows the locally-configured (not yet applied) slots as a compact list.
class _PendingSlotsList extends StatelessWidget {
  final Map<int, List<_TimeSlot>> slots;
  final String unit;
  final void Function(int day, int index) onRemove;
  const _PendingSlotsList({
    required this.slots,
    required this.unit,
    required this.onRemove,
  });
  static const _dayNames = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];

  @override
  Widget build(BuildContext context) {
    final entries = slots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          for (int i = 0; i < entry.value.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: _kTeal.withValues(alpha: 0.4), width: 1),
                borderRadius: BorderRadius.circular(6),
                color: _kTeal.withValues(alpha: 0.05),
              ),
              child: Row(children: [
                const Icon(Icons.schedule, color: _kTeal, size: 18),
                const SizedBox(width: 8),
                Text(
                  _dayNames[entry.key],
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold, color: _kTeal),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.value[i].time.hour.toString().padLeft(2,'0')}:'
                  '${entry.value[i].time.minute.toString().padLeft(2,'0')}'
                  '  ·  ${entry.value[i].duration}$unit',
                  style: const TextStyle(fontSize: 13),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => onRemove(entry.key, i),
                  child: const Icon(Icons.close, size: 18, color: Colors.red),
                ),
              ]),
            ),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  final _EventModel event;
  const _EventTile({required this.event});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey[300]!, width: 1),
      borderRadius: BorderRadius.circular(6),
      color: Colors.grey[50],
    ),
    child: Row(children: [
      Icon(event.fromLastEvent ? Icons.autorenew : Icons.event,
          color: _kTeal, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(event.scheduleStr,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        Text('${event.durationStr}  ·  ${event.repeatStr}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ])),
    ]),
  );
}
