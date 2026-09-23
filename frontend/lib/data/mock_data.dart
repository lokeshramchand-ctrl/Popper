import 'package:uuid/uuid.dart';
import 'local_db.dart';
import '../models/log_entry.dart';

class MockData {
  static Future<void> seed({
    bool clearFirst = true,
    int days = 10,
  }) async {
    final uuid = const Uuid();

    if (clearFirst) {
      await LocalDB.box.clear(); // reset for UI testing
    }

    for (int i = 0; i < days; i++) {
      final day = DateTime.now().subtract(Duration(days: i));

      // simulate 1–2 entries per day randomly
      final entriesPerDay = (i % 2 == 0) ? 1 : 2;

      for (int j = 0; j < entriesPerDay; j++) {
        final time = DateTime(
          day.year,
          day.month,
          day.day,
          7 + (j * 3), // 7AM, 10AM variation
          (i * 7) % 60,
        );

        final entry = LogEntry(
          id: uuid.v4(),
          timestamp: time,
          isSynced: true,
        );

        await LocalDB.save(entry);
      }
    }
  }
}