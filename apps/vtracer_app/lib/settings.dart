import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-facing preferences: theme mode, locale override, and the Needle3
/// endpoint used by the AI auto mode.
///
/// Theme and locale default to following the OS; a persisted choice survives
/// restarts. The detail sub-window loads the same preferences for consistent
/// theming/language across windows.
class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs, this.themeMode, this.localeOverride,
      this.needle3Endpoint);

  static const _themeKey = 'settings.themeMode';
  static const _localeKey = 'settings.locale';
  static const _needle3Key = 'settings.needle3Endpoint';

  final SharedPreferences _prefs;

  ThemeMode themeMode;

  /// null = follow the system locale.
  Locale? localeOverride;

  /// Endpoint of a `needle --serve` process for AI auto decisions; empty =
  /// use the built-in offline heuristics.
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

  Future<void> setNeedle3Endpoint(String value) async {
    final endpoint = value.trim();
    if (endpoint == needle3Endpoint) return;
    needle3Endpoint = endpoint;
    notifyListeners();
    await _prefs.setString(_needle3Key, endpoint);
  }
}
