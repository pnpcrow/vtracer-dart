import 'package:test/test.dart';
import 'package:vtracer/vtracer.dart';
import 'package:vtracer_ai/vtracer_ai.dart';

void main() {
  final engine = HeuristicDecisionEngine();

  test('bimodal grayscale → binary clustering', () async {
    final d = await engine.decide(
      const ImageFeatures(
        width: 800, height: 600, megapixels: 0.48, aspectRatio: 1.33,
        quantizedColors: 4, paletteShare8: 0.99, dominantShare: 0.6,
        edgeDensity: 0.15, meanGradient: 20, flatShare: 0.8, noiseLevel: 0.2,
        colorfulness: 2, transparentShare: 0, luminanceSpread: 255,
        darkShare: 0.45, lightShare: 0.5, backgroundUniformity: 1.5,
      ),
      TuningGoal.balanced,
    );
    expect(d.clustering, Clustering.binary);
    expect(d.fitMode, FitMode.spline);
    expect(d.source, DecisionSource.heuristic);
    expect(d.confidence, greaterThanOrEqualTo(0.55));
    expect(d.confidence, lessThanOrEqualTo(0.95));
    expect(d.rationale, isNotEmpty);
  });

  test('uneven lighting scans go adaptive', () async {
    final d = await engine.decide(
      const ImageFeatures(
        width: 800, height: 600, megapixels: 0.48, aspectRatio: 1.33,
        quantizedColors: 16, paletteShare8: 0.9, dominantShare: 0.4,
        edgeDensity: 0.1, meanGradient: 15, flatShare: 0.85, noiseLevel: 1.0,
        colorfulness: 5, transparentShare: 0, luminanceSpread: 200,
        darkShare: 0.3, lightShare: 0.4, backgroundUniformity: 30,
      ),
      TuningGoal.balanced,
    );
    expect(d.clustering, Clustering.binary);
    expect(d.binaryAdaptive, isTrue);
  });

  test('poster-like palette → color clustering, mosaic on flat art', () async {
    final d = await engine.decide(
      const ImageFeatures(
        width: 800, height: 600, megapixels: 0.48, aspectRatio: 1.33,
        quantizedColors: 40, paletteShare8: 0.95, dominantShare: 0.3,
        edgeDensity: 0.08, meanGradient: 8, flatShare: 0.85, noiseLevel: 0.5,
        colorfulness: 35, transparentShare: 0, luminanceSpread: 180,
        darkShare: 0.1, lightShare: 0.2, backgroundUniformity: 4,
      ),
      TuningGoal.balanced,
    );
    expect(d.clustering, Clustering.colorCluster);
    expect(d.hierarchical, Hierarchical.cutout);
    expect(d.maxColors, isNull);
  });

  test('photo-like → coarse stacked layers', () async {
    final d = await engine.decide(
      const ImageFeatures(
        width: 1920, height: 1080, megapixels: 2.07, aspectRatio: 1.78,
        quantizedColors: 900, paletteShare8: 0.25, dominantShare: 0.04,
        edgeDensity: 0.2, meanGradient: 18, flatShare: 0.3, noiseLevel: 4,
        colorfulness: 40, transparentShare: 0, luminanceSpread: 220,
        darkShare: 0.1, lightShare: 0.05, backgroundUniformity: 25,
      ),
      TuningGoal.balanced,
    );
    expect(d.clustering, Clustering.colorCluster);
    expect(d.filterSpeckle, 8);
    expect(d.layerDifference, 48);
    expect(d.colorPrecision, 8);
  });

  test('goal shifts the photo profile: faithful vs compact', () async {
    final f = const ImageFeatures(
      width: 800, height: 600, megapixels: 0.48, aspectRatio: 1.33,
      quantizedColors: 900, paletteShare8: 0.25, dominantShare: 0.04,
      edgeDensity: 0.2, meanGradient: 18, flatShare: 0.3, noiseLevel: 4,
      colorfulness: 40, transparentShare: 0, luminanceSpread: 220,
      darkShare: 0.1, lightShare: 0.05, backgroundUniformity: 25,
    );
    final faithful = await engine.decide(f, TuningGoal.faithful);
    final compact = await engine.decide(f, TuningGoal.compact);

    expect(faithful.filterSpeckle, lessThan(compact.filterSpeckle));
    expect(faithful.layerDifference, lessThan(compact.layerDifference));
    expect(faithful.simplify, isNull);
    expect(compact.simplify, isNotNull);
    expect(compact.maxColors, isNotNull);
  });
}
