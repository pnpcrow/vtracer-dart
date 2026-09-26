import 'dart:convert';

import 'package:test/test.dart';
import 'package:vtracer/vtracer.dart';
import 'package:vtracer_ai/vtracer_ai.dart';

/// A fake runtime returning a canned body.
class FakeRuntime implements Needle3Runtime {
  final Object? body;
  final Needle3Exception? error;
  Needle3Invocation? lastInvocation;

  FakeRuntime(this.body, {this.error});

  @override
  Future<Needle3Answer> run(Needle3Invocation invocation) async {
    lastInvocation = invocation;
    if (error != null) throw error!;
    return parseNeedle3Answer(body);
  }
}

Map<String, Object?> fullAnswer({
  String clustering = 'color-cluster',
  int colorPrecision = 7,
  int layerDifference = 48,
  int filterSpeckle = 8,
  int maxColors = 24,
  double simplify = 1.5,
}) =>
    {
      'function_calls': [
        {
          'name': 'propose_vtracer_parameters',
          'arguments': {
            'clustering': clustering,
            'hierarchical': 'stacked',
            'fit_mode': 'spline',
            'filter_speckle': filterSpeckle,
            'color_precision': colorPrecision,
            'layer_difference': layerDifference,
            'corner_threshold': 120,
            'segment_length': 4.5,
            'splice_threshold': 45,
            'max_colors': maxColors,
            'simplify': simplify,
            'binary_threshold': 128,
            'binary_adaptive': false,
            'watershed_detail': 128,
            'rationale': 'high noise and diffuse palette suggest photo mode',
            'confidence': 0.82,
          },
        },
      ],
      'reasoning': 'photo-like statistics',
      'confidence': 0.82,
    };

const features = ImageFeatures(
  width: 800, height: 600, megapixels: 0.48, aspectRatio: 1.33,
  quantizedColors: 900, paletteShare8: 0.25, dominantShare: 0.04,
  edgeDensity: 0.2, meanGradient: 18, flatShare: 0.3, noiseLevel: 4,
  colorfulness: 40, transparentShare: 0, luminanceSpread: 220,
  darkShare: 0.1, lightShare: 0.05, backgroundUniformity: 25,
);

void main() {
  test('full valid answer is used as-is with model metadata', () async {
    final engine = Needle3DecisionEngine(runtime: FakeRuntime(fullAnswer()));
    final d = await engine.decide(features, TuningGoal.balanced);

    expect(d.source, DecisionSource.needle3);
    expect(d.clustering, Clustering.colorCluster);
    expect(d.colorPrecision, 7);
    expect(d.layerDifference, 48);
    expect(d.maxColors, 24);
    expect(d.simplify, 1.5);
    expect(d.confidence, closeTo(0.82, 1e-9));
    expect(d.rationale, contains('noise'));
  });

  test('tool definition and prompts are attached to the invocation', () async {
    final runtime = FakeRuntime(fullAnswer());
    final engine = Needle3DecisionEngine(runtime: runtime);
    await engine.decide(features, TuningGoal.compact);

    final invocation = runtime.lastInvocation!;
    expect(invocation.tool['name'], DecisionTemplates.toolName);
    final schema = invocation.tool['parameters'] as Map<String, Object?>;
    expect(
        (schema['properties'] as Map<String, Object?>).keys,
        containsAll(['clustering', 'color_precision', 'confidence']));
    expect(invocation.system, contains('compact'));
    expect(invocation.prompt, contains('image_features'));
  });

  test('out-of-range values are clamped and flagged as repaired', () async {
    final body = fullAnswer()
      ..['function_calls'] = [
        {
          'name': 'propose_vtracer_parameters',
          'arguments': {
            ...(fullAnswer()['function_calls'] as List).first['arguments']
                as Map<String, Object?>,
            'color_precision': 99,
            'segment_length': 1.0,
          },
        }
      ];
    final engine = Needle3DecisionEngine(runtime: FakeRuntime(body));
    final d = await engine.decide(features, TuningGoal.balanced);

    expect(d.colorPrecision, 8); // clamped to max
    expect(d.lengthThreshold, 3.5);
    expect(d.source, DecisionSource.needle3Repaired);
  });

  test('missing fields fall back to the heuristic baseline', () async {
    final body = {
      'function_calls': [
        {
          'name': 'propose_vtracer_parameters',
          'arguments': {
            'clustering': 'watershed',
            'watershed_detail': 180,
            'rationale': 'organic edges',
            'confidence': 0.7,
          },
        },
      ],
    };
    final engine = Needle3DecisionEngine(runtime: FakeRuntime(body));
    final d = await engine.decide(features, TuningGoal.balanced);

    expect(d.clustering, Clustering.watershed);
    expect(d.watershedDetail, 180);
    // Baseline (photo profile) kept for everything the model omitted.
    expect(d.colorPrecision, 8);
    expect(d.layerDifference, 48);
    expect(d.source, DecisionSource.needle3Repaired);
  });

  test('arguments as JSON string are decoded', () async {
    final body = {
      'function_calls': [
        {
          'name': 'propose_vtracer_parameters',
          'arguments': jsonEncode(
              (fullAnswer()['function_calls'] as List).first['arguments']),
        },
      ],
    };
    final engine = Needle3DecisionEngine(runtime: FakeRuntime(body));
    final d = await engine.decide(features, TuningGoal.balanced);
    expect(d.colorPrecision, 7);
  });

  test('bare extraction answer (no envelope) is accepted', () async {
    final args = (fullAnswer()['function_calls'] as List).first['arguments']
        as Map<String, Object?>;
    final engine = Needle3DecisionEngine(runtime: FakeRuntime(args));
    final d = await engine.decide(features, TuningGoal.balanced);
    expect(d.layerDifference, 48);
  });

  test('decideOrHeuristic falls back on runtime failure', () async {
    final engine = Needle3DecisionEngine(
      runtime: FakeRuntime(null, error: Needle3Exception('down')),
    );
    final d = await engine.decideOrHeuristic(features, TuningGoal.balanced);
    expect(d.source, DecisionSource.heuristic);
    expect(d.filterSpeckle, 8);
  });

  test('runtime failure propagates from decide()', () async {
    final engine = Needle3DecisionEngine(
      runtime: FakeRuntime(null, error: Needle3Exception('down')),
    );
    await expectLater(
      engine.decide(features, TuningGoal.balanced),
      throwsA(isA<Needle3Exception>()),
    );
  });

  test('engine-reported failure (success:false) throws', () async {
    final body = {
      'type': 'call',
      'success': false,
      'error': 'tool call truncated: token budget exhausted',
      'function_calls': [],
    };
    final engine = Needle3DecisionEngine(runtime: FakeRuntime(body));
    await expectLater(
      engine.decide(features, TuningGoal.balanced),
      throwsA(isA<Needle3Exception>()),
    );
  });

  test('model abstention (success:true, no call) throws', () async {
    final body = {
      'type': 'call',
      'success': true,
      'function_calls': [],
      'suppressed_calls': [],
      'confidence': 0.007,
    };
    final engine = Needle3DecisionEngine(runtime: FakeRuntime(body));
    await expectLater(
      engine.decide(features, TuningGoal.balanced),
      throwsA(isA<Needle3Exception>()),
    );
  });

  test('compact profile sends the minimal prompt set', () async {
    final runtime = FakeRuntime(fullAnswer());
    final engine = Needle3DecisionEngine(
      runtime: runtime,
      promptProfile: PromptProfile.compact,
    );
    await engine.decide(features, TuningGoal.balanced);

    final invocation = runtime.lastInvocation!;
    expect(invocation.system, DecisionTemplates.compactSystemPrompt(TuningGoal.balanced));
    expect(invocation.prompt, contains('image_features'));
    final properties =
        (invocation.tool['parameters'] as Map<String, Object?>)['properties']
            as Map<String, Object?>;
    // Descriptions are stripped so the tiny model keeps its context budget.
    expect(
      properties.values.every((p) => !(p as Map<String, Object?>).containsKey('description')),
      isTrue,
    );
  });
}
