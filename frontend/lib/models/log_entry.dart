import 'package:hive/hive.dart';

part 'log_entry.g.dart';

@HiveType(typeId: 0)
class LogEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime timestamp;

  @HiveField(2)
  bool isSynced;

  LogEntry({
    required this.id,
    required this.timestamp,
    this.isSynced = false,
  });
}