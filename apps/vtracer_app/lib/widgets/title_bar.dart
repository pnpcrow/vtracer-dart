import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../controller.dart';
import '../l10n/app_localizations.dart';
import '../settings.dart';
import 'settings_dialog.dart';

/// Whether this platform needs our custom window caption buttons: Windows
/// and Linux get a fully frameless window; macOS keeps its native traffic
/// lights and the web has no window chrome at all.
bool get showsWindowControls => !kIsWeb && !Platform.isMacOS;

/// The custom title bar that replaces the removed native one: drag to move,
/// double-click to maximize, caption buttons, and the settings entry point.
///
/// The state is needed only for the source-image dimensions readout that
/// used to live in the AppBar actions.
class AppTitleBar extends StatefulWidget {
  final AppState state;
  final SettingsController settings;

  const AppTitleBar({super.key, required this.state, required this.settings});

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (showsWindowControls) {
      windowManager.addListener(this);
      windowManager.isMaximized().then((value) {
        if (mounted) setState(() => _maximized = value);
      });
    }
  }

  @override
  void dispose() {
    if (showsWindowControls) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final titleRow = Row(
      children: [
        // macOS keeps its native traffic lights over the left edge.
        SizedBox(width: !kIsWeb && Platform.isMacOS ? 78 : 14),
        Icon(Icons.format_shapes, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Text(l10n.appTitle, style: theme.textTheme.titleSmall),
        const SizedBox(width: 16),
        Text(
          widget.state.hasImage
              ? '${widget.state.imageWidth}×${widget.state.imageHeight}'
              : '',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: l10n.settingsTitle,
          icon: const Icon(Icons.settings_outlined, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: () => showSettingsDialog(context, widget.settings),
        ),
        const SizedBox(width: 4),
      ],
    );

    return Container(
      height: 40,
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            // DragToMoveArea also toggles maximize on double-click.
            child: kIsWeb ? titleRow : DragToMoveArea(child: titleRow),
          ),
          if (showsWindowControls) ...[
            _CaptionButton(
              icon: Icons.horizontal_rule,
              tooltip: l10n.windowButtonMinimize,
              onTap: () => windowManager.minimize(),
            ),
            _CaptionButton(
              icon: _maximized ? Icons.filter_none : Icons.crop_square,
              tooltip:
                  _maximized ? l10n.windowButtonRestore : l10n.windowButtonMaximize,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _CaptionButton(
              icon: Icons.close,
              tooltip: l10n.windowButtonClose,
              destructive: true,
              onTap: () => windowManager.close(),
            ),
          ],
        ],
      ),
    );
  }
}

/// A Windows-style caption button: flat, wide hover target; the close button
/// hovers red.
class _CaptionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool destructive;

  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.destructive = false,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: double.infinity,
            color: _hovering
                ? (widget.destructive ? scheme.error : scheme.onSurface.withValues(alpha: 0.08))
                : null,
            child: Icon(
              widget.icon,
              size: 17,
              color: _hovering && widget.destructive ? scheme.onError : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
