import 'package:shared_preferences/shared_preferences.dart';

/// Which backend the app talks to.
enum ServerTarget { deployed, localhost, emulator, custom }

// ─────────────────────────────────────────────────────────────────
//  AppConfig  –  runtime settings persisted in SharedPreferences.
//
//  Defaults reproduce the shipped behaviour exactly (deployed server,
//  backdating restricted to dates before today), so a user who never
//  opens the Back Office sees no difference.
// ─────────────────────────────────────────────────────────────────
class AppConfig {
  static const String deployedUrl =
      'https://lt9e0fj1favccw8wxgggl2d2.deploy.splsystems.in';
  static const String localhostUrl = 'http://localhost:3081';

  /// Android emulators reach the host machine's localhost through 10.0.2.2.
  static const String emulatorUrl = 'http://10.0.2.2:3081';

  static const _kTarget = 'cfg_server_target';
  static const _kCustomUrl = 'cfg_custom_url';
  static const _kOpenDates = 'cfg_open_date_range';

  static SharedPreferences? _prefs;

  static ServerTarget _target = ServerTarget.deployed;
  static String _customUrl = '';
  static bool _openDateRange = false;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final t = _prefs!.getString(_kTarget);
    _target = ServerTarget.values.firstWhere(
      (e) => e.name == t,
      orElse: () => ServerTarget.deployed,
    );
    _customUrl = _prefs!.getString(_kCustomUrl) ?? '';
    _openDateRange = _prefs!.getBool(_kOpenDates) ?? false;
  }

  static ServerTarget get target => _target;
  static String get customUrl => _customUrl;

  /// When true the backdate picker accepts any date up to and including
  /// today, reaching back to 2000 instead of 2020.
  static bool get openDateRange => _openDateRange;

  static String urlFor(ServerTarget t) {
    switch (t) {
      case ServerTarget.deployed:
        return deployedUrl;
      case ServerTarget.localhost:
        return localhostUrl;
      case ServerTarget.emulator:
        return emulatorUrl;
      case ServerTarget.custom:
        return _customUrl.isEmpty ? deployedUrl : _customUrl;
    }
  }

  /// The base URL every [ApiService] request is built from.
  static String get baseUrl => urlFor(_target);

  static Future<void> setTarget(ServerTarget t) async {
    _target = t;
    await _prefs?.setString(_kTarget, t.name);
  }

  static Future<void> setCustomUrl(String url) async {
    var clean = url.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    _customUrl = clean;
    await _prefs?.setString(_kCustomUrl, clean);
  }

  static Future<void> setOpenDateRange(bool value) async {
    _openDateRange = value;
    await _prefs?.setBool(_kOpenDates, value);
  }

  /// Restores every setting to its shipped default.
  static Future<void> reset() async {
    await setTarget(ServerTarget.deployed);
    await setCustomUrl('');
    await setOpenDateRange(false);
  }
}
