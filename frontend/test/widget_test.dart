import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:popper/config/app_config.dart';
import 'package:popper/data/local_db.dart';
import 'package:popper/main.dart';
import 'package:popper/models/log_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('popper_test');
    Hive.init(hiveDir.path);
    Hive.registerAdapter(LogEntryAdapter());
    await Hive.openBox<LogEntry>(LocalDB.boxName);
    SharedPreferences.setMockInitialValues({});
    await AppConfig.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp("test-device"));
    await tester.pump(const Duration(seconds: 1));
    // Just verify the app renders something
    expect(find.byType(MyApp), findsOneWidget);
  });

  test('AppConfig defaults to the deployed server', () {
    expect(AppConfig.target, ServerTarget.deployed);
    expect(AppConfig.baseUrl, AppConfig.deployedUrl);
    expect(AppConfig.openDateRange, isFalse);
  });
}
