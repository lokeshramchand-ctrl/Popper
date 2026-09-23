// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../data/local_db.dart';
import '../data/mock_data.dart';
import '../services/api_service.dart';
import '../services/export_service.dart';
import '../services/sync_service.dart';

// ─────────────────────────────────────────────────────────────────
//  BackOfficeScreen  –  hidden configuration panel.
//
//  Reached by tapping the date in the HomeScreen header 7 times
//  within 3 seconds. Deliberately has no visible entry point.
//
//  Sections:
//    SERVER  – deployed / localhost / emulator / custom base URL + ping
//    DATES   – open the backdate picker to today and older years
//    DATA    – export (JSON/CSV), sync, restore, seed, wipe local
//    DEVICE  – device id + local counts
// ─────────────────────────────────────────────────────────────────

class BackOfficeScreen extends StatefulWidget {
  final String deviceId;
  const BackOfficeScreen({super.key, required this.deviceId});

  @override
  State<BackOfficeScreen> createState() => _BackOfficeScreenState();
}

class _BackOfficeScreenState extends State<BackOfficeScreen> {
  // ── Palette (shared with Home / History) ───────────────────────
  static const Color _linen = Color(0xFFEEE8DC);
  static const Color _walnut = Color(0xFF1C1510);
  static const Color _dust = Color(0xFF8C7B68);
  static const Color _rule = Color(0xFFC9BFA8);
  static const Color _terracotta = Color(0xFFB85C38);

  final ApiService _api = ApiService();
  late final SyncService _sync = SyncService(_api);
  late final TextEditingController _customCtrl = TextEditingController(
    text: AppConfig.customUrl,
  );

  String? _pingResult;
  bool _busy = false;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────
  Future<void> _selectTarget(ServerTarget t) async {
    HapticFeedback.selectionClick();
    if (t == ServerTarget.custom) {
      await AppConfig.setCustomUrl(_customCtrl.text);
    }
    await AppConfig.setTarget(t);
    setState(() => _pingResult = null);
  }

  Future<void> _saveCustomUrl() async {
    final url = _customCtrl.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _snack('ENTER A FULL URL, E.G. http://192.168.1.5:3081', false);
      return;
    }
    await AppConfig.setCustomUrl(url);
    await AppConfig.setTarget(ServerTarget.custom);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _pingResult = null);
    _snack('CUSTOM SERVER SAVED', true);
  }

  Future<void> _ping() async {
    setState(() => _pingResult = 'PINGING…');
    final rtt = await _api.ping();
    if (!mounted) return;
    setState(
      () => _pingResult = rtt == null
          ? 'UNREACHABLE'
          : 'OK · ${rtt.inMilliseconds} MS',
    );
  }

  Future<void> _export(ExportFormat f) async {
    final label = f == ExportFormat.json ? 'JSON' : 'CSV';
    await Clipboard.setData(ClipboardData(text: ExportService.render(f)));
    String? path;
    try {
      path = await ExportService.writeFile(f);
    } catch (e) {
      debugPrint('[export] file write failed: $e');
    }
    if (!mounted) return;
    if (path != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => _InfoDialog(
          title: '$label EXPORTED',
          body: 'Copied to clipboard and saved to:\n\n$path',
        ),
      );
    } else {
      _snack('$label COPIED TO CLIPBOARD', true);
    }
  }

  Future<void> _run(String label, Future<String> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final msg = await task();
      _snack(msg, true);
    } catch (e) {
      debugPrint('[back-office] $label failed: $e');
      _snack('$label FAILED', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _InfoDialog(title: title, body: body, confirm: true),
    );
    return ok == true;
  }

  void _snack(String message, bool success) {
    if (!mounted) return;
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
            Expanded(child: Text(message, style: _mono(9, color: _linen))),
          ],
        ),
      ),
    );
  }

  // ── Styles ─────────────────────────────────────────────────────
  static TextStyle _mono(
    double size, {
    Color color = _walnut,
    FontWeight weight = FontWeight.w400,
    double spacing = 1.6,
  }) => TextStyle(
    fontFamily: 'IBMPlexMono',
    color: color,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
  );

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final total = LocalDB.getAll().length;
    final pending = LocalDB.getUnsynced().length;

    return Scaffold(
      backgroundColor: _linen,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _section('SERVER'),
                  for (final t in ServerTarget.values) _targetRow(t),
                  if (AppConfig.target == ServerTarget.custom ||
                      _customCtrl.text.isNotEmpty)
                    _customUrlRow(),
                  _actionRow(
                    'TEST CONNECTION',
                    AppConfig.baseUrl,
                    Icons.network_check,
                    _ping,
                    trailing: _pingResult,
                  ),

                  _section('DATES'),
                  _toggleRow(
                    'OPEN DATE RANGE',
                    'Past entries may use today and any day since 2000',
                    AppConfig.openDateRange,
                    (v) async {
                      await AppConfig.setOpenDateRange(v);
                      setState(() {});
                    },
                  ),

                  _section('DATA'),
                  _actionRow(
                    'EXPORT JSON',
                    'Clipboard + documents folder',
                    Icons.data_object,
                    () => _export(ExportFormat.json),
                  ),
                  _actionRow(
                    'EXPORT CSV',
                    'Clipboard + documents folder',
                    Icons.table_rows_outlined,
                    () => _export(ExportFormat.csv),
                  ),
                  _actionRow(
                    'PUSH PENDING',
                    '$pending entries waiting to sync',
                    Icons.upload,
                    () => _run('SYNC', () async {
                      final n = await _sync.sync(widget.deviceId);
                      return '$n ENTRIES SYNCED';
                    }),
                  ),
                  _actionRow(
                    'PULL FROM SERVER',
                    'Import records missing locally',
                    Icons.download,
                    () => _run('RESTORE', () async {
                      final n = await _sync.restoreFromServer(widget.deviceId);
                      return '$n RECORDS RESTORED';
                    }),
                  ),
                  _actionRow(
                    'SEED SAMPLE DATA',
                    'Adds 10 days of local-only entries',
                    Icons.science_outlined,
                    () async {
                      if (!await _confirm(
                        'SEED SAMPLE DATA',
                        'Adds ~15 fake entries marked as synced. They will '
                            'not be uploaded. Existing entries are kept.',
                      )) {
                        return;
                      }
                      await _run('SEED', () async {
                        await MockData.seed(clearFirst: false);
                        return 'SAMPLE DATA ADDED';
                      });
                    },
                  ),
                  _actionRow(
                    'WIPE LOCAL DATA',
                    'Server copy is untouched',
                    Icons.delete_outline,
                    () async {
                      if (!await _confirm(
                        'WIPE LOCAL DATA',
                        'Deletes all $total entries on this device, including '
                            '$pending not yet synced. This cannot be undone.',
                      )) {
                        return;
                      }
                      await _run('WIPE', () async {
                        await LocalDB.box.clear();
                        return 'LOCAL DATA WIPED';
                      });
                    },
                    danger: true,
                  ),

                  _section('DEVICE'),
                  _actionRow(
                    'DEVICE ID',
                    widget.deviceId,
                    Icons.copy,
                    () async {
                      await Clipboard.setData(
                        ClipboardData(text: widget.deviceId),
                      );
                      _snack('DEVICE ID COPIED', true);
                    },
                  ),
                  _infoRow('LOCAL ENTRIES', '$total'),
                  _infoRow('PENDING SYNC', '$pending'),

                  const SizedBox(height: 20),
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        await AppConfig.reset();
                        _customCtrl.clear();
                        setState(() => _pingResult = null);
                        _snack('SETTINGS RESET', true);
                      },
                      child: Text(
                        'RESET SETTINGS',
                        style: _mono(8, color: _dust, spacing: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Pieces ─────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _rule, width: 1)),
      ),
      child: Row(
        children: [
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
                      Text('BACK', style: _mono(8, color: _dust)),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'BACK OFFICE',
                  style: _mono(10, weight: FontWeight.w600, spacing: 1.8),
                ),
                const SizedBox(height: 2),
                Text('CONFIGURATION', style: _mono(8, color: _dust, spacing: 2)),
              ],
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: _walnut),
            ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _rule, width: 1)),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'PlayfairDisplay',
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w700,
          fontSize: 17,
          color: _walnut,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _rowShell({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: _rule, width: 1)),
        ),
        child: child,
      ),
    );
  }

  Widget _targetRow(ServerTarget t) {
    const labels = {
      ServerTarget.deployed: 'DEPLOYED',
      ServerTarget.localhost: 'LOCALHOST',
      ServerTarget.emulator: 'ANDROID EMULATOR',
      ServerTarget.custom: 'CUSTOM',
    };
    final selected = AppConfig.target == t;
    final url = t == ServerTarget.custom && AppConfig.customUrl.isEmpty
        ? 'Not set'
        : AppConfig.urlFor(t);
    return _rowShell(
      onTap: () => _selectTarget(t),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? _terracotta : Colors.transparent,
              border: selected ? null : Border.all(color: _dust, width: 1),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labels[t]!,
                  style: _mono(
                    9,
                    color: selected ? _terracotta : _walnut,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  url,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(8, color: _dust, spacing: 0.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _customUrlRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _rule, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _customCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              cursorColor: _walnut,
              style: _mono(11, spacing: 0.3),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'http://192.168.1.5:3081',
                hintStyle: _mono(11, color: _rule, spacing: 0.3),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: _rule),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: _walnut),
                ),
              ),
              onSubmitted: (_) => _saveCustomUrl(),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _saveCustomUrl,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: _walnut,
              child: Text(
                'USE',
                style: _mono(7.5, color: _linen, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap, {
    String? trailing,
    bool danger = false,
  }) {
    final ink = danger ? _terracotta : _walnut;
    return _rowShell(
      onTap: _busy ? null : onTap,
      child: Row(
        children: [
          Icon(icon, size: 14, color: ink),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _mono(9, color: ink, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(8, color: _dust, spacing: 0.4),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: _mono(
                8,
                color: trailing.startsWith('OK') ? _terracotta : _dust,
                weight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _toggleRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return _rowShell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _mono(9, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(subtitle, style: _mono(8, color: _dust, spacing: 0.4)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: _linen,
            activeTrackColor: _terracotta,
            inactiveThumbColor: _dust,
            inactiveTrackColor: _rule.withOpacity(0.4),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String title, String value) {
    return _rowShell(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: _mono(8, color: _dust, spacing: 2)),
          Text(value, style: _mono(12, weight: FontWeight.w600, spacing: 0.3)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Square, linen-toned dialog used for confirmations and results.
// ─────────────────────────────────────────────────────────────────
class _InfoDialog extends StatelessWidget {
  final String title;
  final String body;
  final bool confirm;
  const _InfoDialog({
    required this.title,
    required this.body,
    this.confirm = false,
  });

  static const Color _linen = Color(0xFFEEE8DC);
  static const Color _walnut = Color(0xFF1C1510);
  static const Color _dust = Color(0xFF8C7B68);

  @override
  Widget build(BuildContext context) {
    TextStyle mono(double size, Color c, [FontWeight w = FontWeight.w400]) =>
        TextStyle(
          fontFamily: 'IBMPlexMono',
          fontSize: size,
          color: c,
          fontWeight: w,
          letterSpacing: 1.4,
        );
    return Dialog(
      backgroundColor: _linen,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: mono(10, _walnut, FontWeight.w600)),
            const SizedBox(height: 12),
            SelectableText(body, style: mono(9, _dust).copyWith(height: 1.5)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (confirm)
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('CANCEL', style: mono(8.5, _dust)),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    confirm ? 'CONFIRM' : 'DONE',
                    style: mono(8.5, _walnut, FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
