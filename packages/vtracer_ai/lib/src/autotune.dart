import 'package:vtracer/vtracer.dart';

import 'decision.dart';
import 'engine.dart';
import 'features.dart';
import 'needle3.dart';

/// End-to-end outcome of one auto-tune run.
class TuningResult {
  final ImageFeatures features;

  /// The validated, clamped decision.
  final AiDecision decision;

  /// A fresh [VtracerConfig] with the decision applied (a clone of `base`
  /// when one was passed to [AutoTuner.tune]).
  final VtracerConfig config;

  final String engineName;
  final int elapsedMs;

  const TuningResult({
    required this.features,
    required this.decision,
    required this.config,
    required this.engineName,
    required this.elapsedMs,
  });
}

/// Facade: extract features from an image, ask the engine for a decision,
/// validate it, and apply it to a [VtracerConfig].
///
/// ```dart
/// // Deterministic offline tuning (no model needed):
/// final result = await AutoTuner.local().tune(image);
/// final svg = result.config.build().toSvg(image);
///
/// // Through a Needle3 model (serve mode):
/// final tuner = AutoTuner.needle3Serve(Uri.parse('http://127.0.0.1:8080/run'));
/// ```
class AutoTuner {
  final DecisionEngine engine;

  AutoTuner(this.engine);

  /// Heuristic engine — offline, deterministic, always available.
  factory AutoTuner.local() => AutoTuner(HeuristicDecisionEngine());

  /// Needle3 engine against a `needle --serve` endpoint, with heuristic
  /// repair/fallback built in.
  factory AutoTuner.needle3Serve(Uri endpoint, {String model = 'needle3.cact'}) =>
      AutoTuner(Needle3DecisionEngine(
        runtime: Needle3HttpRuntime(endpoint),
        model: model,
      ));

  /// Needle3 engine through the `needle` CLI subprocess.
  factory AutoTuner.needle3Cli(String modelPath, {String? executable}) =>
      AutoTuner(Needle3DecisionEngine(
        runtime: Needle3ProcessRuntime(modelPath: modelPath, executable: executable),
      ));

  Future<TuningResult> tune(
    ColorImage image, {
    TuningGoal goal = TuningGoal.balanced,
    VtracerConfig? base,
  }) async {
    final sw = Stopwatch()..start();
    final features = FeatureExtractor().extract(image);
    final decision = (await engine.decide(features, goal)).clamped();
    final config = (base ?? VtracerConfig.defaultConfig()).clone();
    decision.applyTo(config);
    return TuningResult(
      features: features,
      decision: decision,
      config: config,
      engineName: engine.name,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }
}
