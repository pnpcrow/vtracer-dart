import 'package:flutter/material.dart';

import 'controller.dart';
import 'widgets/canvas_area.dart';
import 'widgets/options_panel.dart';

void main() {
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
            // client attached, rapid semantics commits (slider drags,
            // progress updates) can leave the engine's Windows
            // accessibility bridge desynchronized and crash the process with
            // an access violation in AccessibilityBridge::
            // CreateRemoveReparentedNodesUpdate (null child->parent()
            // dereference; the guarding assert is compiled out in release).
            // Excluding semantics empties the update stream entirely, which
            // removes the crash surface at the cost of screen-reader support.
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
