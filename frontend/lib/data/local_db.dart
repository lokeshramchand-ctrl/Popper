import 'package:hive_flutter/hive_flutter.dart';
import '../models/log_entry.dart';

class LocalDB {
  static const boxName = "logs";

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(LogEntryAdapter());
    await Hive.openBox<LogEntry>(boxName);
  }

  static Box<LogEntry> get box => Hive.box<LogEntry>(boxName);

  static Future<void> save(LogEntry entry) async {
    await box.put(entry.id, entry);
  }

  static List<LogEntry> getAll() {
    return box.values.toList();
  }

  static List<LogEntry> getUnsynced() {
    return box.values.where((e) => !e.isSynced).toList();
  }

  /// Uses explicit box.put() instead of entry.save() so the write always
  /// succeeds regardless of the HiveObject's internal box-reference state.
  static Future<void> update(LogEntry entry) async {
    await box.put(entry.id, entry);
  }

  static Future<void> delete(String id) async {
    await box.delete(id);
  }
}