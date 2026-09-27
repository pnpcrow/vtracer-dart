import 'package:test/test.dart';
import 'package:vtracer/vtracer.dart';
import 'package:vtracer_ai/vtracer_ai.dart';

import 'needle3_test.dart' show FakeRuntime, features;

/// A grayscale, strongly bimodal feature set (document/scan-like).
const scanFeatures = ImageFeatures(
  width: 800, height: 600, megapixels: 0.48, aspectRatio: 1.33,
  quantizedColors: 4, paletteShare8: 0.99, dominantShare: 0.6,
  edgeDensity: 0.15, meanGradient: 20, flatShare: 0.8, noiseLevel: 0.2,
  colorfulness: 2, transparentShare: 0, luminanceSpread: 255,
  darkShare: 0.45, lightShare: 0.5, backgroundUniformity: 1.5,
);

void main() {
  test('candidates() offers only color families — never binary', () {
    final menu = HeuristicDecisionEngine().candidates(features, TuningGoal.balanced);

    // Photo-like features: flat and photo are the feasible families.
    expect(menu.map((c) => c.$1), ['A', 'B']);
    expect(
      menu.every((c) => c.$2.clustering != Clustering.binary),
      isTrue,
      reason: 'the destructive binary profile must never reach the auto menu',
    );
  });

  test('candidates() menu is never empty (flat and photo are unconditional)',
      () {
    for (final goal in TuningGoal.values) {
      expect(
        HeuristicDecisionEngine().candidates(features, goal),
        isNotEmpty,
      );
    }
  });

  test('scanDirect detects document/scan inputs deterministically', () {
    final direct =
        HeuristicDecisionEngine().scanDirect(scanFeatures, TuningGoal.balanced);

    expect(direct, isNotNull);
    expect(direct!.clustering, Clustering.binary);
    expect(direct.rationale, contains('document/scan'));
    // Colorful images never take the scan route.
    expect(
      HeuristicDecisionEngine().scanDirect(features, TuningGoal.balanced),
      isNull,
    );
  });

  test('dispatched choice selects the candidate with model metadata',
      () async {
    final runtime = FakeRuntime({
      'function_calls': [
        {
          'name': 'choose_candidate',
          'arguments': {'choice': 'A'},
        },
      ],
      'reasoning': 'flat palette dominates the image',
      'confidence': 0.77,
    });
    final engine = Needle3CandidateEngine(
      runtime: runtime,
      rotateCandidates: false, // letter→family mapping is the shipped order
    );
    final d = await engine.decide(features, TuningGoal.balanced);

    expect(d.source, DecisionSource.needle3);
    expect(d.confidence, closeTo(0.77, 1e-9));
    expect(d.rationale, startsWith('model choice: A'));
    // A = flat family for these features.
    expect(d.clustering, Clustering.colorCluster);
    expect(d.layerDifference, 24);
    // The engine sees the chooser invocation, not the big decision schema.
    expect(runtime.lastInvocation!.tool['name'], 'choose_candidate');
    // The tool enum covers exactly the presented letters.
    final schema = runtime.lastInvocation!.tool['parameters']
        as Map<String, Object?>;
    final choice = (schema['properties']
        as Map<String, Object?>)['choice'] as Map<String, Object?>;
    expect(choice['enum'], ['A', 'B']);
  });

  test('scan features take the deterministic route without the model',
      () async {
    final runtime = FakeRuntime({
      'function_calls': [
        {
          'name': 'choose_candidate',
          'arguments': {'choice': 'A'},
        },
      ],
    });
    final engine = Needle3CandidateEngine(runtime: runtime);
    final d = await engine.decide(scanFeatures, TuningGoal.balanced);

    expect(d.clustering, Clustering.binary);
    expect(d.source, DecisionSource.heuristic);
    expect(runtime.lastInvocation, isNull,
        reason: 'the model must not be consulted for scans');
  });

  test('invalid letter throws so callers can fall back', () async {
    final engine = Needle3CandidateEngine(runtime: FakeRuntime({
      'function_calls': [
        {
          'name': 'choose_candidate',
          'arguments': {'choice': 'Z'},
        },
      ],
    }));
    await expectLater(
      engine.decide(features, TuningGoal.balanced),
      throwsA(isA<Needle3Exception>()),
    );
  });

  test('missing letter throws so callers can fall back', () async {
    final engine = Needle3CandidateEngine(runtime: FakeRuntime({
      'function_calls': [
        {'name': 'choose_candidate', 'arguments': {}},
      ],
    }));
    await expectLater(
      engine.decide(features, TuningGoal.balanced),
      throwsA(isA<Needle3Exception>()),
    );
  });

  test('candidate rotation is deterministic for the same image', () async {
    final runtime = FakeRuntime({
      'function_calls': [
        {
          'name': 'choose_candidate',
          'arguments': {'choice': 'A'},
        },
      ],
    });
    final engine = Needle3CandidateEngine(runtime: runtime);
    await engine.decide(features, TuningGoal.balanced);
    final prompt1 = runtime.lastInvocation!.prompt;
    await engine.decide(features, TuningGoal.balanced);
    final prompt2 = runtime.lastInvocation!.prompt;
    expect(prompt1, prompt2);
  });
}
