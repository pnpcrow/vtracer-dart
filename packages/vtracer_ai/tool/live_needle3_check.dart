import 'dart:io';

import 'package:vtracer_ai/vtracer_ai.dart';

/// Live check against a real Needle3 engine: runs one decision end to end
/// through the bundled engine + model with the compact prompt profile.
///
/// ```sh
/// dart run packages/vtracer_ai/tool/live_needle3_check.dart
/// ```
Future<void> main() async {
  final root = Directory.current.path;
  final engine = '$root/apps/vtracer_app/assets/needle3/needle.exe';
  final model = '$root/apps/vtracer_app/assets/needle3/needle3.cact';
  if (!File(engine).existsSync() || !File(model).existsSync()) {
    stderr.writeln('bundled engine/model not found under apps/vtracer_app/assets/needle3/');
    exitCode = 1;
    return;
  }

  const features = ImageFeatures(
    width: 1920, height: 1080, megapixels: 2.07, aspectRatio: 1.78,
    quantizedColors: 900, paletteShare8: 0.25, dominantShare: 0.04,
    edgeDensity: 0.2, meanGradient: 18, flatShare: 0.3, noiseLevel: 4,
    colorfulness: 40, transparentShare: 0, luminanceSpread: 220,
    darkShare: 0.1, lightShare: 0.05, backgroundUniformity: 25,
  );
  const goal = TuningGoal.balanced;

  final engine_ = Needle3DecisionEngine(
    runtime: Needle3EmbeddedRuntime(
      enginePath: engine,
      modelPath: model,
      timeout: const Duration(minutes: 5),
    ),
    // The base 121M model only completes with the minimal prompt profile.
    promptProfile: PromptProfile.compact,
  );

  final sw = Stopwatch()..start();
  final decision = await engine_.decideOrHeuristic(features, goal);
  sw.stop();
  stdout.writeln('source:   ${decision.source}');
  stdout.writeln('decision: ${decision.toSummary()}');
  stdout.writeln('rationale: ${decision.rationale}');
  stdout.writeln('elapsed:  ${sw.elapsedMilliseconds} ms');
}
