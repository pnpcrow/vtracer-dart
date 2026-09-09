import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings.dart';

Future<void> showSettingsDialog(
  BuildContext context,
  SettingsController settings,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => SettingsDialog(settings: settings),
  );
}

/// App-level settings: theme mode and language. Each choice carries a short
/// helper description so the effect of the setting is clear without trying
/// it out.
class SettingsDialog extends StatelessWidget {
  final SettingsController settings;

  const SettingsDialog({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.settingsTitle),
      content: SizedBox(
        width: 460,
        child: AnimatedBuilder(
          animation: settings,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsTheme,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(l10n.settingsThemeSystem),
                    icon: const Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(l10n.settingsThemeLight),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(l10n.settingsThemeDark),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (selection) =>
                    settings.setThemeMode(selection.first),
              ),
              const SizedBox(height: 6),
              _HelperText(
                text: switch (settings.themeMode) {
                  ThemeMode.system => l10n.settingsThemeSystemDesc,
                  ThemeMode.light => l10n.settingsThemeLightDesc,
                  ThemeMode.dark => l10n.settingsThemeDarkDesc,
                },
              ),
              const SizedBox(height: 20),
              Text(l10n.settingsLanguage,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'system',
                    label: Text(l10n.settingsLanguageSystem),
                    icon: const Icon(Icons.translate),
                  ),
                  ButtonSegment(value: 'en', label: Text(l10n.settingsLanguageEn)),
                  ButtonSegment(value: 'ko', label: Text(l10n.settingsLanguageKo)),
                ],
                selected: {
                  settings.localeOverride?.languageCode ?? 'system',
                },
                onSelectionChanged: (selection) => settings.setLocaleOverride(
                  selection.first == 'system' ? null : Locale(selection.first),
                ),
              ),
              const SizedBox(height: 6),
              _HelperText(
                text: switch (settings.localeOverride?.languageCode) {
                  'en' => l10n.settingsLanguageEnDesc,
                  'ko' => l10n.settingsLanguageKoDesc,
                  _ => l10n.settingsLanguageSystemDesc,
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.settingsClose),
        ),
      ],
    );
  }
}

/// Small muted explanation line under a setting; cross-fades when the
/// selection changes.
class _HelperText extends StatelessWidget {
  final String text;

  const _HelperText({required this.text});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text(
        text,
        key: ValueKey<String>(text),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
