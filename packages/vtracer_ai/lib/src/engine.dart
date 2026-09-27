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
/// This is both the always-available fallback (no model, no network) and
/// the candidate factory for the chooser-style model engines
/// (`Needle3CandidateEngine`).
///
/// Candidate menu policy: only **color families** are offered to the model.
/// The binary (document/scan) profile is intentionally excluded — it is the
/// one candidate that is destructive by nature (everything lighter than the
/// threshold is discarded), so a biased model pick could silently reduce an
/// image to its outlines. Binary is reachable through the explicit B/W mode
/// (which [AutoTuner.tune]'s `preserveBinary` respects) and through the
/// strict deterministic [scanDirect] detector.
class HeuristicDecisionEngine implements DecisionEngine {
  @override
  String get name => 'heuristic';

  /// The color-family menu. Each family carries a feasibility predicate; a
  /// family is only presented to the model when its predicate holds, so
  /// every menu item is safe to pick for the image at hand. `flat` and
  /// `photo` are unconditional generalists — the menu is never empty.
  static final List<({
    String id,
    bool Function(ImageFeatures) feasible,
    AiDecision Function(ImageFeatures, TuningGoal) build,
  })> _families = [
    (
      id: 'flat',
      feasible: (_) => true,
      build: _flatArt,
    ),
    (
      id: 'line-illustration',
      feasible: _lineIllustrationFeasible,
      build: _lineIllustration,
    ),
    (
      id: 'gradient-illustration',
      feasible: _gradientIllustrationFeasible,
      build: _gradientIllustration,
    ),
    (
      id: 'photo',
      feasible: (_) => true,
      build: _photo,
    ),
    (
      id: 'pixel-icon',
      feasible: _pixelIconFeasible,
      build: _pixelIcon,
    ),
  ];

  /// The feasible color families for one image, labeled A, B, C… in menu
  /// order. Letters are positional over the presented menu.
  List<(String, AiDecision)> candidates(ImageFeatures f, TuningGoal goal) {
    final letters = 'ABCDE'.split('');
    var i = 0;
    final menu = <(String, AiDecision)>[];
    for (final family in _families) {
      if (!family.feasible(f)) continue;
      if (i >= letters.length) break;
      menu.add((letters[i++], family.build(f, goal)));
    }
    return menu;
  }

  /// The binary (document/scan) profile — not part of the auto menu, but
  /// reachable when the user explicitly selected B/W (see
  /// [AutoTuner.tune]'s `preserveBinary`).
  AiDecision lineArtCandidate(ImageFeatures f, TuningGoal goal) =>
      _lineArt(f, goal);

  /// Strict deterministic detector for document/scan inputs: near-grayscale
  /// and strongly bimodal luminance. When it matches, auto mode applies the
  /// binary profile directly without consulting the model (the model cannot
  /// see content, so this decision is the rules' to make). Returns null for
  /// everything else.
  AiDecision? scanDirect(ImageFeatures f, TuningGoal goal) {
    if (f.colorfulness < 14 && f.darkShare + f.lightShare > 0.7) {
      final lineArt = _lineArt(f, goal);
      return lineArt.withMeta(
        rationale:
            'document/scan detected (near-grayscale, strongly bimodal) — '
            '${lineArt.rationale}',
      );
    }
    return null;
  }

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

  /// Binary document/scan profile. Destructive on color images by design —
  /// only reached through the explicit B/W mode or [scanDirect].
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

  static bool _lineIllustrationFeasible(ImageFeatures f) =>
      f.edgeDensity > 0.08 && f.lightShare > 0.45 && f.colorfulness >= 14;

  /// Colored strokes on a light background: fine color clustering keeps
  /// both the strokes and the fills alive (binary would discard the fills).
  static AiDecision _lineIllustration(ImageFeatures f, TuningGoal goal) => AiDecision(
        clustering: Clustering.colorCluster,
        hierarchical: Hierarchical.stacked,
        fitMode: FitMode.spline,
        filterSpeckle: goal == TuningGoal.faithful ? 1 : 2,
        colorPrecision: 8,
        layerDifference: goal == TuningGoal.compact ? 20 : 12,
        cornerThreshold: 60,
        lengthThreshold: 4.0,
        spliceThreshold: 45,
        maxColors: null,
        simplify: goal == TuningGoal.compact ? 1.0 : null,
        binaryThreshold: 128,
        binaryAdaptive: false,
        watershedDetail: 128,
        rationale:
            'Colored line work on a light background (edge density '
            '${f.edgeDensity.toStringAsFixed(2)}, colorfulness '
            '${f.colorfulness.toStringAsFixed(0)}) — fine color clustering '
            'preserves strokes and fills alike.',
        source: DecisionSource.heuristic,
        goal: goal,
      );

  static bool _gradientIllustrationFeasible(ImageFeatures f) =>
      f.flatShare > 0.4 && f.colorfulness > 20 && f.noiseLevel < 2.5;

  /// Smooth gradients over flat regions: full color precision and a mid
  /// gradient step keep banding down without exploding the layer count.
  static AiDecision _gradientIllustration(ImageFeatures f, TuningGoal goal) =>
      AiDecision(
        clustering: Clustering.colorCluster,
        hierarchical: Hierarchical.stacked,
        fitMode: FitMode.spline,
        filterSpeckle: goal == TuningGoal.faithful
            ? 4
            : goal == TuningGoal.compact
                ? 8
                : 6,
        colorPrecision: 8,
        layerDifference: goal == TuningGoal.faithful
            ? 24
            : goal == TuningGoal.compact
                ? 40
                : 32,
        cornerThreshold: 120,
        lengthThreshold: 4.0,
        spliceThreshold: 45,
        maxColors: null,
        simplify: goal == TuningGoal.faithful ? null : 1.0,
        binaryThreshold: 128,
        binaryAdaptive: false,
        watershedDetail: 128,
        rationale:
            'Smooth gradients over flat regions (flat share '
            '${f.flatShare.toStringAsFixed(2)}, low noise) — fine layers at '
            'a mid gradient step keep banding down.',
        source: DecisionSource.heuristic,
        goal: goal,
      );

  static AiDecision _flatArt(ImageFeatures f, TuningGoal goal) {
    final mosaic = f.flatShare > 0.55 && f.paletteShare8 > 0.75;
    // Interpolation: a more diffuse palette needs a bigger gradient step,
    // or the near-identical shades fragment into many layers.
    final layerDifference = switch (goal) {
      TuningGoal.faithful => 12,
      TuningGoal.balanced => f.paletteShare8 > 0.9 ? 16 : 24,
      TuningGoal.compact => 28,
    };
    return AiDecision(
      clustering: Clustering.colorCluster,
      hierarchical: mosaic ? Hierarchical.cutout : Hierarchical.stacked,
      fitMode: FitMode.spline,
      filterSpeckle: goal == TuningGoal.faithful ? 2 : 4,
      colorPrecision: f.quantizedColors > 24 ? 8 : 6,
      layerDifference: layerDifference,
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

  static AiDecision _photo(ImageFeatures f, TuningGoal goal) {
    // Interpolated from features: noisier images tolerate (and need) more
    // aggressive speckle removal; steeper gradients collapse into fewer,
    // coarser layers.
    final speckle = switch (goal) {
      TuningGoal.faithful => 2,
      TuningGoal.balanced => (f.noiseLevel / 4).round().clamp(4, 12),
      TuningGoal.compact => 12,
    };
    final layerDiff = switch (goal) {
      TuningGoal.faithful => (f.meanGradient * 1.5).round().clamp(24, 40),
      TuningGoal.balanced => (f.meanGradient * 2).round().clamp(32, 64),
      TuningGoal.compact => (f.meanGradient * 2.5).round().clamp(48, 96),
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

  static bool _pixelIconFeasible(ImageFeatures f) =>
      f.megapixels <= 0.1 && f.quantizedColors <= 32;

  /// Tiny images with tiny palettes: the exact pixel lattice preserves hard
  /// edges; spline smoothing would blur them.
  static AiDecision _pixelIcon(ImageFeatures f, TuningGoal goal) => AiDecision(
        clustering: Clustering.colorCluster,
        hierarchical: Hierarchical.stacked,
        fitMode: FitMode.pixel,
        filterSpeckle: 1,
        colorPrecision: 8,
        layerDifference: 16,
        cornerThreshold: 60,
        lengthThreshold: 4.0,
        spliceThreshold: 45,
        maxColors: null,
        simplify: null,
        binaryThreshold: 128,
        binaryAdaptive: false,
        watershedDetail: 128,
        rationale:
            'Tiny image with a tiny palette (${f.quantizedColors} colors, '
            '${f.megapixels.toStringAsFixed(2)} MP) — exact pixel lattice '
            'preserves hard edges.',
        source: DecisionSource.heuristic,
        goal: goal,
      );
}

enum _ImageClass { lineArt, flatArt, photo }
