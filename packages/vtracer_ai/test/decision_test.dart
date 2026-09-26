import 'package:test/test.dart';
import 'package:vtracer/vtracer.dart';
import 'package:vtracer_ai/vtracer_ai.dart';

void main() {
  test('clamped() forces every parameter into pipeline range', () {
    final d = const AiDecision(
      clustering: Clustering.colorCluster,
      hierarchical: Hierarchical.stacked,
      fitMode: FitMode.spline,
      filterSpeckle: 999,
      colorPrecision: 0,
      layerDifference: 300,
      cornerThreshold: -5,
      lengthThreshold: 1.0,
      spliceThreshold: 999,
      maxColors: 1,
      simplify: 99.0,
      binaryThreshold: 999,
      binaryAdaptive: false,
      watershedDetail: 4,
      confidence: 2.0,
    ).clamped();

    expect(d.filterSpeckle, 128);
    expect(d.colorPrecision, 1);
    expect(d.layerDifference, 255);
    expect(d.cornerThreshold, 0);
    expect(d.lengthThreshold, 3.5);
    expect(d.spliceThreshold, 180);
    expect(d.maxColors, 2);
    expect(d.simplify, 10.0);
    expect(d.binaryThreshold, 255);
    expect(d.watershedDetail, 16);
    expect(d.confidence, 1.0);
  });

  test('applyTo() mutates the config it is given', () {
    final cfg = VtracerConfig.defaultConfig();
    const AiDecision(
      clustering: Clustering.watershed,
      hierarchical: Hierarchical.cutout,
      fitMode: FitMode.polygon,
      filterSpeckle: 7,
      colorPrecision: 7,
      layerDifference: 42,
      cornerThreshold: 90,
      lengthThreshold: 5.0,
      spliceThreshold: 30,
      maxColors: 12,
      simplify: 1.5,
      binaryThreshold: 64,
      binaryAdaptive: true,
      watershedDetail: 200,
    ).applyTo(cfg);

    expect(cfg.clustering, Clustering.watershed);
    expect(cfg.hierarchical, Hierarchical.cutout);
    expect(cfg.mode, FitMode.polygon);
    expect(cfg.filterSpeckle, 7);
    expect(cfg.colorPrecision, 7);
    expect(cfg.layerDifference, 42);
    expect(cfg.cornerThreshold, 90);
    expect(cfg.lengthThreshold, 5.0);
    expect(cfg.spliceThreshold, 30);
    expect(cfg.maxColors, 12);
    expect(cfg.simplify, 1.5);
    expect(cfg.binaryThreshold, 64);
    expect(cfg.binaryAdaptive, isTrue);
    expect(cfg.watershedDetail, 200);
  });

  test('fromConfig() captures the config so applyTo reproduces it', () {
    final cfg = VtracerConfig(clustering: Clustering.binary, maxColors: 8);
    final d = AiDecision.fromConfig(cfg);
    final rebuilt = VtracerConfig.defaultConfig();
    d.applyTo(rebuilt);
    expect(rebuilt.clustering, Clustering.binary);
    expect(rebuilt.maxColors, 8);
  });

  test('TuningGoal.parse maps strings', () {
    expect(TuningGoal.parse('faithful'), TuningGoal.faithful);
    expect(TuningGoal.parse('compact'), TuningGoal.compact);
    expect(TuningGoal.parse('whatever'), TuningGoal.balanced);
  });
}
