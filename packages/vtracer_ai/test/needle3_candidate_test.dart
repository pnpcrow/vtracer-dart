import 'package:test/test.dart';
import 'package:vtracer/vtracer.dart';
import 'package:vtracer_ai/vtracer_ai.dart';

import 'needle3_test.dart' show FakeRuntime, features;

void main() {
  test('candidates() exposes the three class profiles', () {
    final engine = HeuristicDecisionEngine();
    final candidates = engine.candidates(features, TuningGoal.balanced);

    expect(candidates.map((c) => c.$1), ['A', 'B', 'C']);
    expect(candidates[0].$2.clustering, Clustering.binary); // line art
    expect(candidates[1].$2.clustering, Clustering.colorCluster); // flat art
    expect(candidates[2].$2.clustering, Clustering.colorCluster); // photo
    expect(candidates[2].$2.filterSpeckle, 8); // photo speckle
  });

  test('dispatched choice selects the candidate with model metadata',
      () async {
    final runtime = FakeRuntime({
      'function_calls': [
        {
          'name': 'choose_candidate',
          'arguments': {'choice': 'B'},
        },
      ],
      'reasoning': 'flat palette dominates the image',
      'confidence': 0.77,
    });
    final engine = Needle3CandidateEngine(
      runtime: runtime,
      rotateCandidates: false, // letter→class mapping is the shipped order
    );
    final d = await engine.decide(features, TuningGoal.balanced);

    expect(d.source, DecisionSource.needle3);
    expect(d.confidence, closeTo(0.77, 1e-9));
    expect(d.rationale, startsWith('model choice: B'));
    // B = flat art profile for these photo-like features: color cluster with
    // the moderate gradient step.
    expect(d.clustering, Clustering.colorCluster);
    expect(d.layerDifference, 20);
    // The engine sees the chooser invocation, not the big decision schema.
    expect(runtime.lastInvocation!.tool['name'], 'choose_candidate');
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
    // Rotation reorders the letters relative to the shipped order.
    expect(prompt1, isNot(contains('A = {"clustering":"binary"')));
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
}
