import 'package:vtracer/vtracer.dart';

import 'decision.dart';
import 'engine.dart';
import 'features.dart';
import 'needle3.dart';
import 'schema.dart';

/// Chooser-style Needle3 engine: the heuristic engine proposes the feasible
/// color-family candidates (flat / line illustration / gradient
/// illustration / photo / pixel icon — never the destructive binary
/// profile), and the model selects the letter of the one that best matches
/// the image features.
///
/// This design exists because the base 121M Needle3 model cannot reliably
/// author a 14-field parameter object zero-shot (measured failure modes:
/// plain-text replies, repetition loops, grounding-suppressed calls — see
/// docs/ai_auto/needle3_integration.md §3.1). A single-enum choice is tiny
/// output and trivially grounded, so the engine dispatches it; the selected
/// candidate is already validated and clamped.
///
/// Two measured/verified safety properties:
/// * Document/scan inputs never reach the model — [scanDirect] on the
///   candidate engine applies the binary profile deterministically when the
///   near-grayscale + strongly-bimodal conditions hold.
/// * The base model's choice carries a position/letter bias (it tends to
///   pick the last-listed letter regardless of content). By default the
///   presentation order is rotated with a deterministic per-image offset so
///   the bias spreads across the color families instead of always landing
///   on the same profile. Content-based choice quality is a fine-tuning
///   matter (§5 of the integration guide).
class Needle3CandidateEngine implements DecisionEngine {
  final Needle3Runtime runtime;
  final HeuristicDecisionEngine candidatesEngine;

  /// Rotate the candidate presentation order deterministically per image
  /// (mitigates the base model's letter bias).
  final bool rotateCandidates;

  Needle3CandidateEngine({
    required this.runtime,
    HeuristicDecisionEngine? candidatesEngine,
    this.rotateCandidates = true,
  }) : candidatesEngine = candidatesEngine ?? HeuristicDecisionEngine();

  @override
  String get name => 'needle3';

  @override
  Future<AiDecision> decide(ImageFeatures features, TuningGoal goal) async {
    // Document/scan route: the strict detector decides without the model.
    final direct = candidatesEngine.scanDirect(features, goal);
    if (direct != null) return direct;

    final candidates = candidatesEngine.candidates(features, goal);
    var presented = candidates;
    if (rotateCandidates) {
      // Deterministic per-image offset derived from the features. The
      // letters stay fixed at their positions and the CONTENT rotates
      // behind them, so a letter-biased model spreads its picks across the
      // families instead of always landing on the same one.
      final offset =
          (features.quantizedColors * 7 + features.width + features.height) %
              candidates.length;
      presented = [
        for (var i = 0; i < candidates.length; i++)
          (candidates[i].$1, candidates[(offset + i) % candidates.length].$2),
      ];
    }
    final byLetter = {for (final (letter, d) in presented) letter: d};
    final prompts =
        DecisionTemplates.chooserPrompts(features, goal, presented);
    final answer = await runtime.run(Needle3Invocation(
      system: prompts.system,
      prompt: prompts.prompt,
      tool: prompts.tool,
    ));

    final letter = answer.arguments['choice'];
    final selected = letter is String ? byLetter[letter.trim().toUpperCase()] : null;
    if (selected == null) {
      throw Needle3Exception(
          'model choice is not one of the presented letters: '
          '${letter ?? '(missing)'}');
    }
    // Defensive invariant: the auto menu never contains the binary family,
    // so a picked candidate must never be binary. If a future change
    // reintroduces it, fail into the heuristic fallback rather than
    // silently discarding the image's colors.
    if (selected.clustering == Clustering.binary) {
      throw Needle3Exception('chooser returned the excluded binary family');
    }
    // The model's `reasoning` trace is often degenerate repetition on the
    // base model, so the UI shows the candidate's own rationale instead;
    // the chosen letter is kept for transparency.
    return selected.withMeta(
      rationale: 'model choice: $letter — ${selected.rationale}',
      confidence: (answer.confidence ?? selected.confidence).toDouble(),
      source: DecisionSource.needle3,
    ).clamped();
  }
}
