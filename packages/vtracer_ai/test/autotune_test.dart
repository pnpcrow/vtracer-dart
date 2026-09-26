import 'package:test/test.dart';
import 'package:vtracer/vtracer.dart';
import 'package:vtracer_ai/vtracer_ai.dart';

import 'features_test.dart';

void main() {
  test('local tuner end-to-end: flat image converts with the tuned config',
      () async {
    final image = flatImage(64, 48);
    final result = await AutoTuner.local().tune(image);

    expect(result.engineName, 'heuristic');
    expect(result.decision.source, DecisionSource.heuristic);
    expect(result.config.clustering, result.decision.clustering);
    expect(result.features.quantizedColors, lessThanOrEqualTo(2));

    // The tuned config must build a working pipeline.
    final svg = result.config.build().toSvg(image);
    expect(svg, contains('<svg'));
    expect(svg, contains('<path'));
  });

  test('tuner respects the goal and the base config', () async {
    final image = posterImage(48, 48);
    final base = VtracerConfig(clustering: Clustering.binary);
    final result = await AutoTuner.local()
        .tune(image, goal: TuningGoal.compact, base: base);

    // Decision overrides the base's clustering fields...
    expect(result.config.clustering, isNot(Clustering.binary));
    // ...but keeps non-decision fields untouched.
    expect(result.config.pathPrecision, base.pathPrecision);
    expect(result.decision.maxColors, isNotNull);
  });

  test('goal faithful keeps simplify off', () async {
    final result =
        await AutoTuner.local().tune(posterImage(48, 48), goal: TuningGoal.faithful);
    expect(result.decision.simplify, isNull);
  });
}
