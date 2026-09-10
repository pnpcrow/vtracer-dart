import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-facing preferences: theme mode and locale override.
///
/// Both default to following the OS; a persisted choice survives restarts.
/// The detail sub-window loads the same preferences for consistent
/// theming/language across windows.
class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs, this.themeMode, this.localeOverride);

  static const _themeKey = 'settings.themeMode';
  static const _localeKey = 'settings.locale';

  final SharedPreferences _prefs;

  ThemeMode themeMode;

  /// null = follow the system locale.
  Locale? localeOverride;

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
}
