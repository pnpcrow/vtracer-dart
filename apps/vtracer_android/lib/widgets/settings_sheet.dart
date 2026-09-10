import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings.dart';

/// Opens the appearance settings bottom sheet (theme + language).
Future<void> showSettingsSheet(BuildContext context, SettingsController settings) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => SettingsSheet(settings: settings),
  );
}

/// Theme and language preferences; both default to following the OS and a
/// chosen value persists across restarts (see [SettingsController]).
class SettingsSheet extends StatelessWidget {
  final SettingsController settings;

  const SettingsSheet({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.settingsTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  l10n.settingsTheme,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              RadioGroup<ThemeMode>(
                groupValue: settings.themeMode,
                onChanged: (m) => settings.setThemeMode(m!),
                child: Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.system,
                      title: Text(l10n.settingsThemeSystem),
                      subtitle: Text(l10n.settingsThemeSystemDesc),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.light,
                      title: Text(l10n.settingsThemeLight),
                      subtitle: Text(l10n.settingsThemeLightDesc),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.dark,
                      title: Text(l10n.settingsThemeDark),
                      subtitle: Text(l10n.settingsThemeDarkDesc),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  l10n.settingsLanguage,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              RadioGroup<String>(
                groupValue: settings.localeOverride?.languageCode ?? 'system',
                onChanged: (code) => settings.setLocaleOverride(
                  code == 'system' ? null : Locale(code!),
                ),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'system',
                      title: Text(l10n.settingsLanguageSystem),
                      subtitle: Text(l10n.settingsLanguageSystemDesc),
                    ),
                    RadioListTile<String>(
                      value: 'en',
                      title: Text(l10n.settingsLanguageEn),
                      subtitle: Text(l10n.settingsLanguageEnDesc),
                    ),
                    RadioListTile<String>(
                      value: 'ko',
                      title: Text(l10n.settingsLanguageKo),
                      subtitle: Text(l10n.settingsLanguageKoDesc),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
