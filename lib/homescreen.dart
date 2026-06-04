// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'log_entry.dart';
import 'local_db.dart';
import 'api_service.dart';
import 'sync_service.dart';

// ─────────────────────────────────────────────────────────────────
//  DESIGN SYSTEM  –  "Apothecary Logbook"
//
//  Palette:
//    Linen      #EEE8DC   bg — aged paper
//    Walnut     #1C1510   primary ink
//    Dust       #8C7B68   muted / secondary
//    Rule       #C9BFA8   dividers
//    Terracotta #B85C38   accent (logged state only)
//
//  Fonts:
//    Display  – Playfair Display Italic  (hero status word)
//    Mono     – IBM Plex Mono            (labels, timestamps, buttons)
// ─────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final String deviceId;
  const HomeScreen({super.key, required this.deviceId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ── Logic ──────────────────────────────────────────────────────
  final api = ApiService();
  late SyncService sync;
  bool doneToday = false; // true if at least one entry exists today
  int todayCount = 0; // how many times logged today
  DateTime? lastTime;

  // ── UI state ───────────────────────────────────────────────────
  bool _isLogging = false;
  bool _isSyncing = false;

  // ── Controllers ────────────────────────────────────────────────
  late AnimationController _stampCtrl;
  late AnimationController _pageCtrl;
  late AnimationController _pressCtrl;

  late Animation<double> _stampScale;
  late Animation<double> _stampOpacity;
  late Animation<double> _stampRotate;
  late Animation<double> _pageFade;
  late Animation<Offset> _pageSlide;
  late Animation<double> _pressScale;

  // ── Palette ────────────────────────────────────────────────────
  static const Color _linen = Color(0xFFEEE8DC);
  static const Color _walnut = Color(0xFF1C1510);
  static const Color _dust = Color(0xFF8C7B68);
  static const Color _rule = Color(0xFFC9BFA8);
  static const Color _terracotta = Color(0xFFB85C38);

  @override
  void initState() {
    super.initState();
    sync = SyncService(api);

    // Stamp: elastic crash-in
    _stampCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _stampScale = CurvedAnimation(parent: _stampCtrl, curve: Curves.elasticOut);
    _stampOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _stampCtrl,
        curve: const Interval(0, 0.3, curve: Curves.easeIn),
      ),
    );
    _stampRotate = Tween<double>(
      begin: -0.19,
      end: -0.07,
    ).animate(CurvedAnimation(parent: _stampCtrl, curve: Curves.elasticOut));

    // Page: fade + rise
    _pageCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _pageFade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _pageCtrl, curve: Curves.easeOut));
    _pageSlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _pageCtrl, curve: Curves.easeOut));

    // Button press: tactile squish
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _pressScale = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeIn));

    load();
  }

  @override
  void dispose() {
    _stampCtrl.dispose();
    _pageCtrl.dispose();
    _pressCtrl.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────
  Future<void> load() async {
    final logs = LocalDB.getAll();
    final today = DateTime.now();

    if (logs.isNotEmpty) {
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      lastTime = logs.first.timestamp;
    }

    // doneToday = at least one entry today
    doneToday = logs.any(
      (e) =>
          e.timestamp.day == today.day &&
          e.timestamp.month == today.month &&
          e.timestamp.year == today.year,
    );

    // todayCount = total entries today (may be > 1)
    todayCount = logs
        .where(
          (e) =>
              e.timestamp.day == today.day &&
              e.timestamp.month == today.month &&
              e.timestamp.year == today.year,
        )
        .length;

    setState(() {});

    _pageCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 190));
    _stampCtrl.forward();

    setState(() => _isSyncing = true);
    await sync.sync(widget.deviceId);
    if (mounted) setState(() => _isSyncing = false);
  }

  // ── Add log ───────────────────────────────────────────────────────
  // Guard: only block concurrent taps, NOT repeat logs.
  // The user may go multiple times per day — every tap is valid.
  Future<void> addLog() async {
    if (_isLogging) return; // debounce only; doneToday never blocks
    HapticFeedback.mediumImpact();

    await _pressCtrl.forward();
    await _pressCtrl.reverse();

    setState(() => _isLogging = true);

    final id = const Uuid().v4();
    final now = DateTime.now();
    final entry = LogEntry(id: id, timestamp: now);
    await LocalDB.save(entry);

    setState(() {
      doneToday = true;
      todayCount += 1;
      lastTime = now;
      _isLogging = false;
    });

    _stampCtrl.forward(from: 0);

    setState(() => _isSyncing = true);
    await sync.sync(widget.deviceId);
    if (mounted) setState(() => _isSyncing = false);
  }

  // ── Formatting ──────────────────────────────────────────────────
  String _pad(int v) => v.toString().padLeft(2, '0');

  String _formatLast(DateTime dt) {
    final today = DateTime.now();
    final isToday =
        dt.day == today.day && dt.month == today.month && dt.year == today.year;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = _pad(dt.minute);
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    final pfx = isToday ? 'Today' : '${_pad(dt.day)}/${_pad(dt.month)}';
    return '$pfx  $h:$m $ap';
  }

  String _headerDate() {
    const days = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final d = DateTime.now();
    return '${days[d.weekday % 7]}  ${_pad(d.day)} ${months[d.month - 1]} ${d.year}';
  }

  // Hero status word — reflects count when > 1
  String _heroWord() {
    if (!doneToday) return 'Not yet.';
    if (todayCount == 1) return 'Wented.';
    return 'Wented\n×$todayCount'; // e.g. "Went ×3"
  }

  // Sub-label under the hero word
  String _subLabel() {
    if (!doneToday) return 'AWAITING · TODAY';
    if (todayCount == 1) return 'LOGGED · TODAY';
    return 'LOGGED · $todayCount× · TODAY';
  }

  // CTA button label — always tappable
  String _ctaLabel() {
    if (!doneToday) return 'I WENT';
    return 'I WENT AGAIN'; // inviting, not blocking
  }

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

    return Scaffold(
      backgroundColor: _linen,
      body: SafeArea(
        child: FadeTransition(
          opacity: _pageFade,
          child: SlideTransition(position: _pageSlide, child: _buildLayout()),
        ),
      ),
    );
  }

  Widget _buildLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopBar(),
          _buildHRule(),
          Expanded(child: _buildStage()),
          _buildLastRow(),
          const SizedBox(height: 20),
          _buildCTA(),
          const SizedBox(height: 8),
          _buildHistoryTap(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _headerDate(),
                style: const TextStyle(
                  fontFamily: 'IBMPlexMono',
                  color: _walnut,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.8,
                ),
              ),
            
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _linen,
                  ),
                ),
                const SizedBox(width: 5),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: const TextStyle(fontFamily: 'IBMPlexMono'),
                  child: Text(""),

                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHRule() => Container(height: 1, color: _rule);

  // ── Stage ────────────────────────────────────────────────────────
  Widget _buildStage() {
    final accent = doneToday ? _terracotta : _walnut;
    final ghostChar = doneToday ? 'L' : '?';

    return Stack(
      alignment: Alignment.center,
      children: [
        // Ghost background letter
        Text(
          ghostChar,
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontStyle: FontStyle.italic,
            fontSize: 220,
            height: 1,
            color: doneToday
                ? _terracotta.withOpacity(0.05)
                : _walnut.withOpacity(0.04),
          ),
        ),

        // Animated stamp
        AnimatedBuilder(
          animation: _stampCtrl,
          builder: (_, _) => Opacity(
            opacity: _stampOpacity.value,
            child: Transform.rotate(
              angle: _stampRotate.value,
              child: Transform.scale(
                scale: _stampScale.value,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Hero word — shows count when > 1
                    Text(
                      _heroWord(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                        fontSize: 68,
                        height: 0.9,
                        letterSpacing: -2,
                        color: accent,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Horizontal rule under word
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 180,
                      height: 1.5,
                      color: accent,
                    ),

                    const SizedBox(height: 8),

                    // Sub-label
                    Text(
                      _subLabel(),
                      style: TextStyle(
                        fontFamily: 'IBMPlexMono',
                        color: accent.withOpacity(0.45),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Last recorded row ────────────────────────────────────────────
  Widget _buildLastRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _rule, width: 1),
          bottom: BorderSide(color: _rule, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _rule, width: 1),
            ),
            child: Icon(Icons.schedule_outlined, size: 14, color: _dust),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LAST RECORDED',
                style: TextStyle(
                  fontFamily: 'IBMPlexMono',
                  color: _dust,
                  fontSize: 7.5,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  fontFamily: 'IBMPlexMono',
                  color: lastTime != null && doneToday ? _terracotta : _walnut,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
                child: Text(
                  lastTime != null ? _formatLast(lastTime!) : 'No entry yet',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Primary CTA ──────────────────────────────────────────────────
  // Button is ALWAYS active — user can log multiple times per day.
  Widget _buildCTA() {
    return ScaleTransition(
      scale: _pressScale,
      child: GestureDetector(
        onTap: addLog, // never null — doneToday does NOT disable
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          height: 52,
          // Stays walnut (active) whether first or subsequent log
          color: _walnut,
          child: Center(
            child: _isLogging
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFFEEE8DC),
                    ),
                  )
                : Text(
                    _ctaLabel(), // "I WENT" / "I WENT AGAIN"
                    style: TextStyle(
                      fontFamily: 'IBMPlexMono',
                      color: const Color(0xFFEEE8DC),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ── History link ─────────────────────────────────────────────────
  Widget _buildHistoryTap() {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/history').then((_) {
        // Refresh in case backdated entries were added on history screen
        if (mounted) load();
      }),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        height: 36,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'VIEW HISTORY',
              style: TextStyle(
                fontFamily: 'IBMPlexMono',
                color: _dust,
                fontSize: 8.5,
                letterSpacing: 2.6,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward, color: _dust, size: 11),
          ],
        ),
      ),
    );
  }
}
