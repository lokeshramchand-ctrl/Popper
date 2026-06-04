import 'package:flutter/foundation.dart';
import 'local_db.dart';
import 'api_service.dart';
import 'log_entry.dart';

class SyncService {
  final ApiService api;

  SyncService(this.api);

  /// Syncs all unsynced local entries to the server.
  /// Returns the number of successfully synced entries.
  /// Only marks an entry as synced after the server confirms success (2xx).
  Future<int> sync(String deviceId) async {
    final unsynced = LocalDB.getUnsynced();
    int synced = 0;

    for (var log in unsynced) {
      try {
        await api.createLog(deviceId, log.id, log.timestamp);
        // Only reaches here if createLog did NOT throw (i.e., server returned 2xx)
        log.isSynced = true;
        await LocalDB.update(log); // uses box.put() — always reliable
        synced++;
        debugPrint('[SyncService] synced entry ${log.id}');
      } catch (e) {
        // Server error or network failure — leave isSynced = false, retry next time
        debugPrint('[SyncService] failed to sync ${log.id}: $e');
      }
    }

    debugPrint('[SyncService] synced $synced / ${unsynced.length}');
    return synced;
  }

  Future<int> restoreFromServer(String deviceId) async {
    final remoteLogs = await api.fetchRecords(deviceId);
    final localIds = LocalDB.getAll().map((e) => e.id).toSet();

    int imported = 0;

    for (final item in remoteLogs) {
      if (localIds.contains(item.id)) {
        continue;
      }

      await LocalDB.save(
        LogEntry(
          id: item.id,
          timestamp: item.timestamp.toUtc(),
          isSynced: true,
        ),
      );

      imported++;
    }

    return imported;
  }

}
