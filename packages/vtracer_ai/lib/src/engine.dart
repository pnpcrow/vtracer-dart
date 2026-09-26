import 'dart:math' as math;

import 'package:vtracer/vtracer.dart';

import 'decision.dart';
import 'features.dart';

/// Anything that can turn image features into a validated decision.
abstract class DecisionEngine {
  String get name;

  Future<AiDecision> decide(ImageFeatures features, TuningGoal goal);
}

/// Deterministic, offline rule engine: classifies the image from its
/// features and maps the class + goal to a parameter set.
///
/// This is both the always-available fallback (no model, no network) and the
/// baseline that repairs partial model outputs in `Needle3DecisionEngine`.
class HeuristicDecisionEngine implements DecisionEngine {
  @override
  String get name => 'heuristic';

  @override
  Future<AiDecision> decide(ImageFeatures f, TuningGoal goal) async {
    final scores = _classScores(f);
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final winner = sorted.first;
    final runnerUp = sorted.length > 1 ? sorted[1].value : 0.0;

    final AiDecision decision;
    switch (winner.key) {
      case _ImageClass.lineArt:
        decision = _lineArt(f, goal);
      case _ImageClass.flatArt:
        decision = _flatArt(f, goal);
      case _ImageClass.photo:
        decision = _photo(f, goal);
    }
    // Confidence from the classification margin: a clear winner scores high.
    final margin =
        (winner.value - runnerUp) / math.max(0.001, winner.value.abs());
    final confidence = (0.55 + 0.4 * margin.clamp(0.0, 1.0)).clamp(0.0, 0.95);
    return AiDecision(
      clustering: decision.clustering,
      hierarchical: decision.hierarchical,
      fitMode: decision.fitMode,
      filterSpeckle: decision.filterSpeckle,
      colorPrecision: decision.colorPrecision,
      layerDifference: decision.layerDifference,
      cornerThreshold: decision.cornerThreshold,
      lengthThreshold: decision.lengthThreshold,
      spliceThreshold: decision.spliceThreshold,
      maxColors: decision.maxColors,
      simplify: decision.simplify,
      binaryThreshold: decision.binaryThreshold,
      binaryAdaptive: decision.binaryAdaptive,
      watershedDetail: decision.watershedDetail,
      rationale: decision.rationale,
      confidence: confidence.toDouble(),
      source: DecisionSource.heuristic,
      goal: goal,
    ).clamped();
  }

  Map<_ImageClass, double> _classScores(ImageFeatures f) {
    // Line art: grayscale-ish, concentrated palette, bimodal luminance.
    final lineArt =
        (f.isGrayscaleish ? 1.0 : 0.15) +
            (f.paletteShare8 > 0.85 ? 1.0 : 0.3) +
            (f.quantizedColors <= 24 ? 1.0 : 0.2) +
            (f.darkShare + f.lightShare > 0.6 ? 1.0 : 0.2) +
            (f.noiseLevel < 2.0 ? 0.8 : 0.1);
    // Flat art: few effective colors, mostly flat regions, low noise.
    final flatArt =
        (f.paletteShare8 > 0.75 ? 1.0 : 0.2) +
            (f.quantizedColors <= 96 ? 1.0 : 0.2) +
            (f.flatShare > 0.5 ? 1.0 : 0.3) +
            (f.noiseLevel < 2.5 ? 1.0 : 0.2) +
            (f.isGrayscaleish ? 0.3 : 1.0);
    // Photo: many colors, diffuse palette, texture/noise, smooth gradients.
    final photo =
        (f.quantizedColors > 96 ? 1.0 : 0.15) +
            (f.paletteShare8 < 0.55 ? 1.0 : 0.2) +
            (f.noiseLevel > 1.5 ? 1.0 : 0.2) +
            (f.isGrayscaleish ? 0.2 : 1.0) +
            (f.meanGradient > 12 ? 0.8 : 0.3);
    return {
      _ImageClass.lineArt: lineArt,
      _ImageClass.flatArt: flatArt,
      _ImageClass.photo: photo,
    };
  }

  AiDecision _lineArt(ImageFeatures f, TuningGoal goal) {
    // Bimodal scans: cut at the luminance valley; uneven lighting goes
    // through Bradley-Roth instead of a fixed cutoff.
    final bimodal = f.darkShare + f.lightShare > 0.55;
    return AiDecision(
      clustering: Clustering.binary,
      hierarchical: Hierarchical.stacked,
      fitMode: FitMode.spline,
      filterSpeckle: goal == TuningGoal.faithful ? 1 : 3,
      colorPrecision: 8,
      layerDifference: 16,
      cornerThreshold: 60,
      lengthThreshold: 4.0,
      spliceThreshold: 45,
      maxColors: null,
      simplify: goal == TuningGoal.compact ? 1.0 : null,
      binaryThreshold: bimodal ? 128 : 160,
      binaryAdaptive: !bimodal || f.backgroundUniformity > 12,
      watershedDetail: 128,
      rationale:
          'Grayscale-ish image with concentrated palette and bimodal '
          'luminance (dark=${f.darkShare.toStringAsFixed(2)}, '
          'light=${f.lightShare.toStringAsFixed(2)}) — binary clustering '
          'with speckle ${goal == TuningGoal.faithful ? 1 : 3}.',
      source: DecisionSource.heuristic,
      goal: goal,
    );
  }

  AiDecision _flatArt(ImageFeatures f, TuningGoal goal) {
    final mosaic = f.flatShare > 0.55 && f.paletteShare8 > 0.75;
    return AiDecision(
      clustering: Clustering.colorCluster,
      hierarchical: mosaic ? Hierarchical.cutout : Hierarchical.stacked,
      fitMode: FitMode.spline,
      filterSpeckle: goal == TuningGoal.faithful ? 2 : 4,
      colorPrecision: f.quantizedColors > 24 ? 8 : 6,
      layerDifference: goal == TuningGoal.faithful ? 12 : 20,
      cornerThreshold: 60,
      lengthThreshold: 4.0,
      spliceThreshold: 45,
      maxColors: goal == TuningGoal.compact ? 16 : null,
      simplify: goal == TuningGoal.compact ? 1.2 : null,
      binaryThreshold: 128,
      binaryAdaptive: false,
      watershedDetail: 128,
      rationale:
          'Flat palette (top8=${f.paletteShare8.toStringAsFixed(2)}, '
          '${f.quantizedColors} quantized colors, flat share '
          '${f.flatShare.toStringAsFixed(2)}) — color clustering with '
          '${mosaic ? "seam-free mosaic" : "stacked layers"}.',
      source: DecisionSource.heuristic,
      goal: goal,
    );
  }

  AiDecision _photo(ImageFeatures f, TuningGoal goal) {
    final speckle = switch (goal) {
      TuningGoal.faithful => 4,
      TuningGoal.balanced => 8,
      TuningGoal.compact => 12,
    };
    final layerDiff = switch (goal) {
      TuningGoal.faithful => 32,
      TuningGoal.balanced => 48,
      TuningGoal.compact => 64,
    };
    return AiDecision(
      clustering: Clustering.colorCluster,
      hierarchical: Hierarchical.stacked,
      fitMode: FitMode.spline,
      filterSpeckle: speckle,
      colorPrecision: 8,
      layerDifference: layerDiff,
      cornerThreshold: 180,
      lengthThreshold: 4.0,
      spliceThreshold: 45,
      maxColors: goal == TuningGoal.compact ? 24 : null,
      simplify: switch (goal) {
        TuningGoal.faithful => null,
        TuningGoal.balanced => 1.0,
        TuningGoal.compact => 2.0,
      },
      binaryThreshold: 128,
      binaryAdaptive: false,
      watershedDetail: 128,
      rationale:
          'Photo-like input (${f.quantizedColors} quantized colors, noise '
          '${f.noiseLevel.toStringAsFixed(1)}, palette share '
          '${f.paletteShare8.toStringAsFixed(2)}) — coarse stacked layers '
          'with speckle $speckle and gradient step $layerDiff.',
      source: DecisionSource.heuristic,
      goal: goal,
    );
  }
}

enum _ImageClass { lineArt, flatArt, photo }
