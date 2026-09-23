import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../data/local_db.dart';
import '../models/log_entry.dart';

enum ExportFormat { json, csv }

/// Serialises the local Hive log for backup / inspection.
class ExportService {
  static List<LogEntry> _sorted() =>
      LocalDB.getAll()..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  static String toJson() {
    final entries = _sorted()
        .map(
          (e) => {
            'id': e.id,
            'timestamp': e.timestamp.toUtc().toIso8601String(),
            'isSynced': e.isSynced,
          },
        )
        .toList();
    return const JsonEncoder.withIndent('  ').convert({
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'count': entries.length,
      'entries': entries,
    });
  }

  static String toCsv() {
    final buf = StringBuffer('id,timestamp_utc,timestamp_local,is_synced\n');
    for (final e in _sorted()) {
      buf.writeln(
        '${e.id},${e.timestamp.toUtc().toIso8601String()},'
        '${e.timestamp.toLocal().toIso8601String()},${e.isSynced}',
      );
    }
    return buf.toString();
  }

  static String render(ExportFormat f) =>
      f == ExportFormat.json ? toJson() : toCsv();

  /// Writes the export into the app documents directory and returns the path.
  /// Returns null on web, where there is no writable filesystem.
  static Future<String?> writeFile(ExportFormat f) async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .split('.')
        .first;
    final ext = f == ExportFormat.json ? 'json' : 'csv';
    final file = File('${dir.path}/popper_export_$stamp.$ext');
    await file.writeAsString(render(f));
    return file.path;
  }
}
