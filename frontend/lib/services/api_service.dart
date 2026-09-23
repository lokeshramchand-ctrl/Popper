import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/log_entry.dart';

class ApiService {
  /// Resolved on every call so a server switch applies immediately.
  String get baseUrl => AppConfig.baseUrl;

  /// Hits the health route. Returns round-trip time, or null if unreachable.
  Future<Duration?> ping() async {
    final sw = Stopwatch()..start();
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/'))
          .timeout(const Duration(seconds: 6));
      sw.stop();
      return res.statusCode == 200 ? sw.elapsed : null;
    } catch (e) {
      debugPrint('[ping] $baseUrl failed: $e');
      return null;
    }
  }

  Future<bool> getTodayStatus(String deviceId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/status/today'),
      headers: {'x-device-id': deviceId},
    );

    return jsonDecode(res.body)['done'];
  }

  Future<Map?> getLatest(String deviceId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/logs/latest'),
      headers: {'x-device-id': deviceId},
    );

    return jsonDecode(res.body)['data'];
  }

  Future<List<LogEntry>> fetchRecords(String deviceId) async {
      debugPrint('DEVICE ID = $deviceId');
    final res = await http.get(
      Uri.parse('$baseUrl/logs/recent'),
      headers: {'x-device-id': deviceId},
    );
    
  debugPrint('STATUS = ${res.statusCode}');
  debugPrint('BODY = ${res.body}');

    final data = jsonDecode(res.body)['data'];
    if (data is! List) {
      return <LogEntry>[];
    }
debugPrint('RECORD COUNT = ${data.length}');
    final unique = <String, LogEntry>{};

    for (final item in data.whereType<Map>()) {
      final map = Map<String, dynamic>.from(item as Map);
      final id = map['id']?.toString();
      final timestampValue = map['timestamp'];
      if (id == null || id.isEmpty || timestampValue == null) {
        continue;
      }

      DateTime? timestamp;
      if (timestampValue is String) {
        timestamp = DateTime.tryParse(timestampValue);
      } else if (timestampValue is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timestampValue);
      }
      if (timestamp == null) {
        continue;
      }

      unique[id] = LogEntry(
        id: id,
        timestamp: timestamp,
        isSynced: map['isSynced'] == true,
      );
    }

    final records = unique.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return records;
  }

  /// Throws an [Exception] if the server returns a non-2xx status code.
  /// This ensures [SyncService] only marks entries as synced on real success.
  Future<void> createLog(String deviceId, String id, DateTime time) async {
    final res = await http.post(
      Uri.parse('$baseUrl/log'),
      headers: {'Content-Type': 'application/json', 'x-device-id': deviceId},
      body: jsonEncode({'id': id, 'timestamp': time.toIso8601String()}),
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      debugPrint('[createLog] FAILED ${res.statusCode}: ${res.body}');
      throw Exception('createLog failed: ${res.statusCode} ${res.body}');
    }

    debugPrint('[createLog] OK ${res.statusCode} id=$id');
  }

  Future<List> getRecent(String deviceId) async {
    return fetchRecords(deviceId);
  }

  Future<bool> deleteLog(String deviceId, String id) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/log/$id'),
        headers: {'Content-Type': 'application/json', 'x-device-id': deviceId},
      );
      debugPrint('[deleteLog] DELETE /log/$id → ${res.statusCode} ${res.body}');
      return res.statusCode == 200 ||
          res.statusCode == 204 ||
          res.statusCode == 404;
    } catch (e) {
      debugPrint('[deleteLog] Exception: $e');
      return false;
    }
  }
}
