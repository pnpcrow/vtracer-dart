import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which brain the AI auto mode consults.
enum AiEngineChoice {
  /// The Needle3 model bundled with the app; extracted from assets and run
  /// in-place. Falls back to the built-in rules when unavailable.
  embedded,

  /// A remote `needle --serve` endpoint (advanced).
  serve,

  /// The built-in offline rule engine only.
  heuristic;

  static AiEngineChoice fromName(String? name) =>
      AiEngineChoice.values.firstWhere((c) => c.name == name,
          orElse: () => AiEngineChoice.embedded);
}

/// User-facing preferences: theme mode, locale override, and the AI auto
/// engine (bundled Needle3 / serve endpoint / built-in rules).
///
/// A persisted choice survives restarts. The detail sub-window loads the
/// same preferences for consistent theming/language across windows.
class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs, this.themeMode, this.localeOverride,
      this.aiEngine, this.needle3Endpoint);

  static const _themeKey = 'settings.themeMode';
  static const _localeKey = 'settings.locale';
  static const _needle3Key = 'settings.needle3Endpoint';
  static const _aiEngineKey = 'settings.aiEngine';

  final SharedPreferences _prefs;

  ThemeMode themeMode;

  /// null = follow the system locale.
  Locale? localeOverride;

  /// Which brain the AI auto mode uses.
  AiEngineChoice aiEngine;

  /// Endpoint of a `needle --serve` process; only used when
  /// [aiEngine] is [AiEngineChoice.serve].
  String needle3Endpoint;

  /// Loads the persisted preferences (system defaults when unset).
  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString(_themeKey);
    final localeName = prefs.getString(_localeKey);
    return SettingsController._(
      prefs,
      ThemeMode.values.firstWhere(
        (m) => m.name == themeName,
        orElse: () => ThemeMode.system,
      ),
      localeName == null || localeName == 'system'
          ? null
          : Locale(localeName),
      AiEngineChoice.fromName(prefs.getString(_aiEngineKey)),
      prefs.getString(_needle3Key) ?? '',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == themeMode) return;
    themeMode = mode;
    notifyListeners();
    await _prefs.setString(_themeKey, mode.name);
  }

  Future<void> setLocaleOverride(Locale? locale) async {
    if (locale?.languageCode == localeOverride?.languageCode) return;
    localeOverride = locale;
    notifyListeners();
    await _prefs.setString(
      _localeKey,
      locale?.languageCode ?? 'system',
    );
  }

  Future<void> setAiEngine(AiEngineChoice choice) async {
    if (choice == aiEngine) return;
    aiEngine = choice;
    notifyListeners();
    await _prefs.setString(_aiEngineKey, choice.name);
  }

  Future<void> setNeedle3Endpoint(String value) async {
    final endpoint = value.trim();
    if (endpoint == needle3Endpoint) return;
    needle3Endpoint = endpoint;
    notifyListeners();
    await _prefs.setString(_needle3Key, endpoint);
  }
}
