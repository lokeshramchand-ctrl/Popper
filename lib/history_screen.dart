// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';
import 'local_db.dart';
import 'log_entry.dart';
import 'sync_service.dart';
// ─────────────────────────────────────────────────────────────────
//  HistoryScreen  –  "Apothecary Logbook  /  Log Register"
//
//  Same palette & typography as HomeScreen:
//    Linen      #EEE8DC   bg
//    Walnut     #1C1510   primary ink
//    Dust       #8C7B68   muted
//    Rule       #C9BFA8   dividers
//    Terracotta #B85C38   synced accent
//
//  Additions vs original:
//    • "ADD PAST ENTRY" button in top-bar  (pencil icon)
//    • _showBackdateSheet()  — bottom sheet with date + time pickers
//      - Date must be strictly before today  (today = HomeScreen only)
//      - Time defaults to noon; user can adjust
//      - Saves via LocalDB, refreshes list inline
// ─────────────────────────────────────────────────────────────────

class HistoryScreen extends StatefulWidget {
  final String deviceId;
  const HistoryScreen({super.key, required this.deviceId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  // ── Palette ────────────────────────────────────────────────────
  static const Color _linen = Color(0xFFEEE8DC);
  static const Color _walnut = Color(0xFF1C1510);
  static const Color _dust = Color(0xFF8C7B68);
  static const Color _rule = Color(0xFFC9BFA8);
  static const Color _terracotta = Color(0xFFB85C38);

  // ── Data ───────────────────────────────────────────────────────
  late List<LogEntry> _logs;

  // ── API ────────────────────────────────────────────────────────
  final ApiService _api = ApiService();
  late final SyncService _sync;

  // ── Sync state ─────────────────────────────────────────────────
  bool _isSyncing = false;
  bool _isOnline = false;
  late final Stream<List<ConnectivityResult>> _connectivityStream;

  // ── Animation ─────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _sync = SyncService(_api);
    _loadLogs();
    _initConnectivity();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  Future<void> _restoreHistory() async {
    try {
      final imported = await _sync.restoreFromServer(widget.deviceId);

      setState(() {
        _loadLogs();
      });

      _showSnack('$imported RECORDS RESTORED', true);
    } catch (e) {
      _showSnack('RESTORE FAILED', false);
    }
  }

  Future<void> _initConnectivity() async {
    // Check current status
    final result = await Connectivity().checkConnectivity();
    final online = !result.contains(ConnectivityResult.none);
    if (mounted) setState(() => _isOnline = online);

    // Auto-sync on open if online and there are unsynced entries
    if (online && LocalDB.getUnsynced().isNotEmpty) {
      _runSync(silent: true);
    }

    // Listen for changes
    _connectivityStream = Connectivity().onConnectivityChanged;
    _connectivityStream.listen((results) {
      final nowOnline = !results.contains(ConnectivityResult.none);
      if (mounted) {
        final wasOffline = !_isOnline;
        setState(() => _isOnline = nowOnline);
        // Auto-sync when coming back online
        if (nowOnline && wasOffline && LocalDB.getUnsynced().isNotEmpty) {
          _runSync(silent: true);
        }
      }
    });
  }

  // ── Sync logic ─────────────────────────────────────────────────
  Future<void> _runSync({bool silent = false}) async {
    if (_isSyncing || !_isOnline) return;

    setState(() => _isSyncing = true);

    try {
      await _sync.sync(widget.deviceId);
      if (mounted) {
        // Load fresh data from Hive BEFORE setState so the rebuild sees
        // up-to-date isSynced flags and an accurate unsynced count.
        _loadLogs();
        final unsynced = LocalDB.getUnsynced().length;
        setState(() {});
        if (!silent) {
          _showSnack(
            unsynced == 0 ? 'ALL ENTRIES SYNCED' : '$unsynced ENTRIES PENDING',
            unsynced == 0,
          );
        }
      }
    } catch (_) {
      if (mounted && !silent)
        _showSnack('SYNC FAILED. CHECK CONNECTION.', false);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSnack(String message, bool success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _walnut,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: success ? _terracotta : _dust,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              message,
              style: GoogleFonts.ibmPlexMono(
                color: _linen,
                fontSize: 9,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Delete entry (local + remote) ──────────────────────────────
  Future<void> _deleteEntry(LogEntry entry) async {
    HapticFeedback.mediumImpact();

    // Optimistic local removal
    setState(() {
      _logs.removeWhere((e) => e.id == entry.id);
    });

    // Delete from local DB
    await LocalDB.delete(entry.id);

    // Delete from remote if synced
    if (entry.isSynced) {
      final ok = await _api.deleteLog(widget.deviceId, entry.id);
      if (!ok) {
        // Remote delete failed — restore locally and notify user
        await LocalDB.save(entry);
        if (mounted) {
          setState(() => _loadLogs());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: _walnut,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              content: Text(
                'REMOTE DELETE FAILED. ENTRY RESTORED.',
                style: GoogleFonts.ibmPlexMono(
                  color: _linen,
                  fontSize: 9,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          );
        }
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _walnut,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              Expanded(
                child: Text(
                  'ENTRY DELETED',
                  style: GoogleFonts.ibmPlexMono(
                    color: _linen,
                    fontSize: 9,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ── Confirm delete sheet ────────────────────────────────────────
  Future<void> _confirmDelete(LogEntry entry) async {
    HapticFeedback.lightImpact();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        final dt = entry.timestamp;
        final timeStr = _time12(dt);
        final ampm = _ampm(dt);
        final dateStr =
            '${_dayAbbr(dt)}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFEEE8DC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 6),
                  width: 32,
                  height: 3,
                  color: _rule,
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: _rule, width: 1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DELETE ENTRY',
                            style: GoogleFonts.ibmPlexMono(
                              color: _walnut,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'THIS CANNOT BE UNDONE',
                            style: GoogleFonts.ibmPlexMono(
                              color: _terracotta,
                              fontSize: 8,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Icon(Icons.close, size: 16, color: _dust),
                    ),
                  ],
                ),
              ),

              // Entry preview
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: _rule, width: 1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$timeStr $ampm',
                          style: GoogleFonts.ibmPlexMono(
                            color: _walnut,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          dateStr,
                          style: GoogleFonts.ibmPlexMono(
                            color: _dust,
                            fontSize: 9,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (entry.isSynced)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: _terracotta, width: 1),
                        ),
                        child: Text(
                          'SYNCED — WILL DELETE\nFROM SERVER',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.ibmPlexMono(
                            color: _terracotta,
                            fontSize: 7,
                            letterSpacing: 1.2,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: _dust, width: 1),
                        ),
                        child: Text(
                          'LOCAL ONLY',
                          style: GoogleFonts.ibmPlexMono(
                            color: _dust,
                            fontSize: 7,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Confirm delete button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, true),
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    color: _walnut,
                    child: Center(
                      child: Text(
                        'DELETE THIS ENTRY',
                        style: GoogleFonts.ibmPlexMono(
                          color: _linen,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Cancel
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, false),
                  child: Text(
                    'CANCEL',
                    style: GoogleFonts.ibmPlexMono(
                      color: _dust,
                      fontSize: 8,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      await _deleteEntry(entry);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _loadLogs() {
    _logs = LocalDB.getAll()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  // ── Backdate sheet ─────────────────────────────────────────────
  Future<void> _showBackdateSheet() async {
    HapticFeedback.lightImpact();

    // Working state inside the sheet
    final today = DateTime.now();
    // Latest selectable: yesterday
    final yesterday = DateTime(today.year, today.month, today.day - 1);

    DateTime selectedDate = yesterday;
    TimeOfDay selectedTime = const TimeOfDay(hour: 12, minute: 0);
    bool isSaving = false;
    String? errorMsg;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            // ── pick date ────────────────────────────────────────
            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: selectedDate,
                firstDate: DateTime(2020),
                lastDate: yesterday, // never today or future
                builder: (context, child) => Theme(
                  data: ThemeData.light().copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFF1C1510),
                      onPrimary: Color(0xFFEEE8DC),
                      surface: Color(0xFFEEE8DC),
                      onSurface: Color(0xFF1C1510),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1C1510),
                      ),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setSheet(() {
                  selectedDate = picked;
                  errorMsg = null;
                });
              }
            }

            // ── pick time ────────────────────────────────────────
            Future<void> pickTime() async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: selectedTime,
                builder: (context, child) => Theme(
                  data: ThemeData.light().copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFF1C1510),
                      onPrimary: Color(0xFFEEE8DC),
                      surface: Color(0xFFEEE8DC),
                      onSurface: Color(0xFF1C1510),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1C1510),
                      ),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setSheet(() {
                  selectedTime = picked;
                  errorMsg = null;
                });
              }
            }

            // ── save ─────────────────────────────────────────────
            Future<void> save() async {
              // Build final DateTime
              final dt = DateTime(
                selectedDate.year,
                selectedDate.month,
                selectedDate.day,
                selectedTime.hour,
                selectedTime.minute,
              );

              // Reject today or future (safety net)
              final todayMidnight = DateTime(
                today.year,
                today.month,
                today.day,
              );
              if (!dt.isBefore(todayMidnight)) {
                setSheet(() => errorMsg = 'DATE MUST BE BEFORE TODAY');
                return;
              }

              setSheet(() => isSaving = true);

              final entry = LogEntry(
                id: const Uuid().v4(),
                timestamp: dt,
                isSynced: false,
              );
              await LocalDB.save(entry);

              if (ctx.mounted) Navigator.pop(ctx);

              // Refresh list on the history screen
              if (mounted) {
                setState(() => _loadLogs());
                HapticFeedback.mediumImpact();
              }
            }

            // ── sheet UI ─────────────────────────────────────────
            final h = selectedTime.hourOfPeriod == 0
                ? 12
                : selectedTime.hourOfPeriod;
            final m = selectedTime.minute.toString().padLeft(2, '0');
            final ap = selectedTime.period == DayPeriod.am ? 'AM' : 'PM';
            final timeStr = '$h:$m $ap';

            const months = [
              'January',
              'February',
              'March',
              'April',
              'May',
              'June',
              'July',
              'August',
              'September',
              'October',
              'November',
              'December',
            ];
            const days = [
              'Monday',
              'Tuesday',
              'Wednesday',
              'Thursday',
              'Friday',
              'Saturday',
              'Sunday',
            ];
            final dateStr =
                '${days[selectedDate.weekday - 1]}, '
                '${selectedDate.day} '
                '${months[selectedDate.month - 1]} '
                '${selectedDate.year}';

            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFEEE8DC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── drag handle ──────────────────────────────
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 6),
                      width: 32,
                      height: 3,
                      color: _rule,
                    ),
                  ),

                  // ── header ───────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _rule, width: 1),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ADD PAST ENTRY',
                                style: GoogleFonts.ibmPlexMono(
                                  color: _walnut,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'FORGOT TO LOG?',
                                style: GoogleFonts.ibmPlexMono(
                                  color: _dust,
                                  fontSize: 8,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // dismiss
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Icon(Icons.close, size: 16, color: _dust),
                        ),
                      ],
                    ),
                  ),

                  // ── date picker row ───────────────────────────
                  _SheetRow(
                    label: 'DATE',
                    value: dateStr,
                    onTap: pickDate,
                    rule: _rule,
                    walnut: _walnut,
                    dust: _dust,
                  ),

                  // ── time picker row ───────────────────────────
                  _SheetRow(
                    label: 'TIME',
                    value: timeStr,
                    onTap: pickTime,
                    rule: _rule,
                    walnut: _walnut,
                    dust: _dust,
                    isLast: errorMsg == null,
                  ),

                  // ── error message ─────────────────────────────
                  if (errorMsg != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                      child: Text(
                        errorMsg!,
                        style: GoogleFonts.ibmPlexMono(
                          color: _terracotta,
                          fontSize: 8,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // ── save button ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                    child: GestureDetector(
                      onTap: isSaving ? null : save,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        height: 50,
                        color: isSaving ? _rule : _walnut,
                        child: Center(
                          child: isSaving
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Color(0xFFEEE8DC),
                                  ),
                                )
                              : Text(
                                  'LOG THIS ENTRY',
                                  style: GoogleFonts.ibmPlexMono(
                                    color: _linen,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 3.0,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── disclaimer ────────────────────────────────
                  Center(
                    child: Text(
                      'ENTRIES BEFORE TODAY ONLY',
                      style: GoogleFonts.ibmPlexMono(
                        color: _dust.withOpacity(0.5),
                        fontSize: 7.5,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Group by calendar month ────────────────────────────────────
  List<_MonthGroup> _grouped() {
    final Map<String, List<LogEntry>> map = {};
    final List<String> order = [];

    for (final e in _logs) {
      final key =
          '${e.timestamp.year}-${e.timestamp.month.toString().padLeft(2, '0')}';
      if (!map.containsKey(key)) {
        map[key] = [];
        order.add(key);
      }
      map[key]!.add(e);
    }

    return order
        .map(
          (k) => _MonthGroup(
            key: k,
            entries: map[k]!,
            sample: map[k]!.first.timestamp,
          ),
        )
        .toList();
  }

  // ── Format helpers ─────────────────────────────────────────────
  String _pad(int v) => v.toString().padLeft(2, '0');

  String _monthName(DateTime dt) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[dt.month - 1]} ${dt.year}';
  }

  String _dayAbbr(DateTime dt) {
    const d = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return d[dt.weekday - 1];
  }

  String _time12(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = _pad(dt.minute);
    return '$h:$m';
  }

  String _ampm(DateTime dt) => dt.hour < 12 ? 'AM' : 'PM';

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFEEE8DC),
      ),
    );

    final groups = _grouped();

    return Scaffold(
      backgroundColor: _linen,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _logs.isEmpty ? _buildEmpty() : _buildList(groups),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
      decoration: BoxDecoration(
        color: _linen,
        border: Border(bottom: BorderSide(color: _rule, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ← Back + title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_ios, size: 11, color: _dust),
                      const SizedBox(width: 4),
                      Text(
                        'BACK',
                        style: TextStyle(
                          fontFamily: 'IBMPlexMono',
                          color: _dust,
                          fontSize: 8,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'LOG REGISTER',
                  style: TextStyle(
                    fontFamily: 'IBMPlexMono',
                    color: _walnut,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ALL ENTRIES',
                  style: TextStyle(
                    fontFamily: 'IBMPlexMono',
                    color: _dust,
                    fontSize: 8,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),

          // Right side: total count + add button
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Total count
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_logs.length}',
                    style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                      fontSize: 34,
                      color: _walnut,
                      height: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'TOTAL RECORDS',
                style: TextStyle(
                  fontFamily: 'IBMPlexMono',
                  color: _dust,
                  fontSize: 7.5,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 10),

              // ── ADD PAST ENTRY button ──────────────────────────
              GestureDetector(
                onTap: _showBackdateSheet,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: _walnut, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, size: 9, color: _walnut),
                      const SizedBox(width: 5),
                      Text(
                        'ADD PAST ENTRY',
                        style: TextStyle(
                          fontFamily: 'IBMPlexMono',
                          color: _walnut,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 6),

              GestureDetector(
                onTap: _isOnline ? _restoreHistory : null,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: _walnut, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download, size: 9, color: _walnut),
                      const SizedBox(width: 5),
                      Text(
                        'RESTORE',
                        style: TextStyle(
                          fontFamily: 'IBMPlexMono',
                          color: _walnut,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // ── FORCE SYNC button ──────────────────────────────
              GestureDetector(
                onTap: _isOnline && !_isSyncing ? () => _runSync() : null,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _isOnline && !_isSyncing
                        ? _walnut
                        : Colors.transparent,
                    border: Border.all(
                      color: _isOnline ? _walnut : _rule,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isSyncing)
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.2,
                            color: _linen,
                          ),
                        )
                      else
                        Icon(
                          _isOnline ? Icons.sync : Icons.sync_disabled,
                          size: 9,
                          color: _isOnline ? _linen : _dust,
                        ),
                      const SizedBox(width: 5),
                      Text(
                        _isSyncing
                            ? 'SYNCING...'
                            : _isOnline
                            ? 'FORCE SYNC'
                            : 'OFFLINE',
                        style: TextStyle(
                          fontFamily: 'IBMPlexMono',
                          color: _isOnline && !_isSyncing ? _linen : _dust,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Empty.',
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
              fontSize: 56,
              color: _walnut.withOpacity(0.08),
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'NO ENTRIES YET',
            style: TextStyle(
              fontFamily: 'IBMPlexMono',
              color: _dust,
              fontSize: 9,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 24),
          // Invite first backdate even from empty state
          GestureDetector(
            onTap: _showBackdateSheet,
            child: Text(
              'ADD A PAST ENTRY →',
              style: TextStyle(
                fontFamily: 'IBMPlexMono',
                color: _walnut,
                fontSize: 8.5,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: _walnut,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Scrollable list ──────────────────────────────────────────────
  Widget _buildList(List<_MonthGroup> groups) {
    final widgets = <Widget>[];
    int delay = 0;

    for (final group in groups) {
      widgets.add(_buildMonthHeader(group, delay));
      delay += 60;
      for (final entry in group.entries) {
        widgets.add(_buildEntryRow(entry, delay));
        delay += 35;
      }
    }

    return ListView(physics: const BouncingScrollPhysics(), children: widgets);
  }

  // ── Month header ─────────────────────────────────────────────────
  Widget _buildMonthHeader(_MonthGroup group, int delayMs) {
    final count = group.entries.length;
    return _DelayedFadeUp(
      delay: Duration(milliseconds: delayMs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: _rule, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _monthName(group.sample),
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: _walnut,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$count ENTR${count == 1 ? 'Y' : 'IES'}',
              style: TextStyle(
                fontFamily: 'IBMPlexMono',
                color: _dust,
                fontSize: 8,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Entry row ────────────────────────────────────────────────────
  Widget _buildEntryRow(LogEntry entry, int delayMs) {
    final isSynced = entry.isSynced;
    // Backdated entries (not today) get a subtle "past" marker
    final today = DateTime.now();
    final isToday =
        entry.timestamp.day == today.day &&
        entry.timestamp.month == today.month &&
        entry.timestamp.year == today.year;
    final isBackdated =
        !isToday &&
        entry.timestamp.isBefore(DateTime(today.year, today.month, today.day));

    return _DelayedFadeUp(
      delay: Duration(milliseconds: delayMs),
      child: Dismissible(
        key: ValueKey(entry.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          await _confirmDelete(entry);
          // We handle actual deletion inside _confirmDelete;
          // return false so Dismissible doesn't auto-remove (we do it via setState)
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          color: _walnut,
          padding: const EdgeInsets.only(right: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline, color: _linen, size: 18),
              const SizedBox(height: 4),
              Text(
                'DELETE',
                style: GoogleFonts.ibmPlexMono(
                  color: _linen,
                  fontSize: 7.5,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: _rule, width: 1)),
            // Very subtle linen tint shift for backdated rows
            color: isBackdated
                ? _walnut.withOpacity(0.015)
                : Colors.transparent,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left gutter: day number + abbr ────────────────
                Container(
                  width: 52,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: _rule, width: 1)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${entry.timestamp.day}',
                        style: TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w700,
                          fontSize: 26,
                          color: _walnut,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _dayAbbr(entry.timestamp),
                        style: TextStyle(
                          fontFamily: 'IBMPlexMono',
                          color: _dust,
                          fontSize: 7,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Body: time + badges ────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Time block
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _time12(entry.timestamp),
                              style: TextStyle(
                                fontFamily: 'IBMPlexMono',
                                color: _walnut,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _ampm(entry.timestamp),
                              style: TextStyle(
                                fontFamily: 'IBMPlexMono',
                                color: _dust,
                                fontSize: 8.5,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ],
                        ),

                        // Badge column: BACKDATED + SYNCED/LOCAL
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // BACKDATED badge — only for past entries
                            if (isBackdated) ...[
                              Text(
                                'BACKDATED',
                                style: TextStyle(
                                  fontFamily: 'IBMPlexMono',
                                  color: _dust.withOpacity(0.55),
                                  fontSize: 6.5,
                                  letterSpacing: 1.2,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            // Sync badge
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSynced
                                        ? _terracotta
                                        : Colors.transparent,
                                    border: isSynced
                                        ? null
                                        : Border.all(color: _dust, width: 1),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isSynced ? 'SYNCED' : 'LOCAL',
                                  style: TextStyle(
                                    fontFamily: 'IBMPlexMono',
                                    color: isSynced ? _terracotta : _dust,
                                    fontSize: 7.5,
                                    letterSpacing: 1.4,
                                    fontWeight: isSynced
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Sheet row: tappable date/time selector row
// ─────────────────────────────────────────────────────────────────
class _SheetRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color rule;
  final Color walnut;
  final Color dust;
  final bool isLast;

  const _SheetRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.rule,
    required this.walnut,
    required this.dust,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: rule, width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'IBMPlexMono',
                color: dust,
                fontSize: 8,
                letterSpacing: 2.0,
              ),
            ),
            Row(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'IBMPlexMono',
                    color: walnut,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.unfold_more, size: 13, color: dust),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Helper: staggered fade-up for list items
// ─────────────────────────────────────────────────────────────────
class _DelayedFadeUp extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _DelayedFadeUp({required this.child, required this.delay});

  @override
  State<_DelayedFadeUp> createState() => _DelayedFadeUpState();
}

class _DelayedFadeUpState extends State<_DelayedFadeUp>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

// ─────────────────────────────────────────────────────────────────
//  Data model helper
// ─────────────────────────────────────────────────────────────────
class _MonthGroup {
  final String key;
  final List<LogEntry> entries;
  final DateTime sample;
  const _MonthGroup({
    required this.key,
    required this.entries,
    required this.sample,
  });
}
