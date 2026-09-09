import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'controller.dart';
import 'detail/detail.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';
import 'theme.dart';
import 'widgets/canvas_area.dart';
import 'widgets/options_panel.dart';
import 'widgets/title_bar.dart';

Future<void> main() async {
  // Sub-windows (the full-detail viewer) run their own engine through this
  // same main(); maybeRunDetailWindow renders the viewer and returns true.
  // It talks over a method channel, so the binding must exist first.
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && await maybeRunDetailWindow()) {
    return;
  }
  final settings = await SettingsController.load();
  if (!kIsWeb) {
    // Chromeless: the native title bar is replaced by AppTitleBar. On
    // Windows/Linux that includes our own caption buttons; macOS keeps its
    // traffic lights over the custom bar.
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: 'VTracer',
      titleBarStyle: TitleBarStyle.hidden,
      minimumSize: Size(760, 480),
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
    });
  }
  runApp(VtracerApp(settings: settings));
}

/// VTracer — raster to vector converter (Pure Dart port of the vtracer
/// desktop/web app).
class VtracerApp extends StatelessWidget {
  const VtracerApp({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => MaterialApp(
        title: 'VTracer',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: settings.themeMode,
        locale: settings.localeOverride,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: HomePage(settings: settings),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings});

  final SettingsController settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AppState _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        return Scaffold(
          body: ExcludeSemantics(
            // Workaround for a Flutter engine bug: with a UI Automation
            // client attached (screen reader, inspection/automation tool),
            // semantics activity can leave the engine's Windows
            // accessibility bridge desynchronized and crash the process with
            // an access violation in AccessibilityBridge::
            // CreateRemoveReparentedNodesUpdate (null child->parent()
            // dereference; the guarding assert is compiled out in release).
            // Excluding semantics empties the commit stream, which removes
            // the slider/progress-driven triggers at the cost of
            // screen-reader support.
            //
            // Known remaining trigger (confirmed by dump analysis:
            // C000041D at flutter_windows.dll+0x3c18a): maximizing the
            // window WHILE a UIA client is attached. Without a UIA client
            // the bridge never activates and the app is stable — verified
            // by maximizing via WM_SYSCOMMAND with no client attached.
            // Revisit once the engine fix ships.
            child: Column(
              children: [
                AppTitleBar(state: _state, settings: widget.settings),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      OptionsPanel(state: _state),
                      const VerticalDivider(width: 1),
                      Expanded(child: CanvasArea(state: _state)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
