/// # vtracer_ai — AI-assisted parameter tuning for vtracer
///
/// vtracer has many "judgment" parameters (clustering strategy, speckle
/// filtering, color precision, gradient layering, curve fitting...) whose
/// ideal values depend entirely on the kind of input image. This package
/// turns that judgment into a structured, model-driven step:
///
/// ```text
/// ColorImage ──▶ FeatureExtractor ──▶ ImageFeatures ──▶ DecisionEngine
///                                                          │
///                        AiDecision ◀──────────────────────┘
///                             │  (validated + clamped)
///                             ▼
///                        VtracerConfig ──▶ Pipeline ──▶ SVG
/// ```
///
/// ## Decision engines
///
/// * [HeuristicDecisionEngine] — deterministic rules on the image features;
///   offline, instant, always available. Also the repair/fallback baseline
///   for model engines.
/// * [Needle3DecisionEngine] — calls a Needle3 model (Cactus Compute's
///   8–29MB on-device function-calling model) through a pluggable
///   [Needle3Runtime] (HTTP serve mode or the `needle` CLI). The JSON
///   schema of the decision, the tool spec and the prompt templates come
///   from [DecisionTemplates], mirroring `docs/ai_auto/templates/`.
///
/// ## Quick start
///
/// ```dart
/// import 'package:vtracer_ai/vtracer_ai.dart';
///
/// // Deterministic offline tuning (no model needed):
/// final result = await AutoTuner.local().tune(image);
/// final svg = result.config.build().toSvg(image);
/// print(result.decision.rationale);
///
/// // Through a Needle3 serve endpoint:
/// final tuner = AutoTuner.needle3Serve(Uri.parse('http://127.0.0.1:8080/run'));
/// final tuned = await tuner.tune(image, goal: TuningGoal.compact);
/// ```
///
/// Every model answer is merged over the heuristic baseline field by field
/// and clamped, so a partial or out-of-range answer can never produce an
/// invalid [VtracerConfig].
library vtracer_ai;

export 'src/autotune.dart';
export 'src/decision.dart';
export 'src/engine.dart';
export 'src/features.dart';
export 'src/needle3.dart';
export 'src/needle3_candidate.dart';
export 'src/needle3_embedded.dart';
export 'src/schema.dart';
