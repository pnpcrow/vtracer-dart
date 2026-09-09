import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'detail/detail.dart';
import 'widgets/canvas_area.dart';
import 'widgets/options_panel.dart';

Future<void> main() async {
  // Sub-windows (the full-detail viewer) run their own engine through this
  // same main(); maybeRunDetailWindow renders the viewer and returns true.
  // It talks over a method channel, so the binding must exist first.
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && await maybeRunDetailWindow()) {
    return;
  }
  runApp(const VtracerApp());
}

/// VTracer — raster to vector converter (Pure Dart port of the vtracer
/// desktop/web app).
class VtracerApp extends StatelessWidget {
  const VtracerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VTracer',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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
          appBar: AppBar(
            title: const Text('VTracer'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    _state.hasImage
                        ? '${_state.imageWidth}×${_state.imageHeight}'
                        : '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
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
            child: Row(
              children: [
                OptionsPanel(state: _state),
                const VerticalDivider(width: 1),
                Expanded(child: CanvasArea(state: _state)),
              ],
            ),
          ),
        );
      },
    );
  }
}
