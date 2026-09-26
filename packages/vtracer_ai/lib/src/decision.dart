import 'package:vtracer/vtracer.dart';

/// What the auto-tuner should optimize for.
enum TuningGoal {
  /// Balanced: good fidelity with a reasonable path/byte budget.
  balanced,

  /// Faithful: prefer detail preservation over compactness.
  faithful,

  /// Compact: prefer fewer shapes / smaller SVG, accepting some smoothing.
  compact;

  static TuningGoal parse(String s) => switch (s) {
        'faithful' => TuningGoal.faithful,
        'compact' => TuningGoal.compact,
        _ => TuningGoal.balanced,
      };
}

/// Where a decision came from.
enum DecisionSource {
  /// The deterministic local rule engine (no model required, offline).
  heuristic,

  /// A Needle3 model call (on-device function-calling model).
  needle3,

  /// A model call that failed validation and was repaired by the rule engine.
  needle3Repaired,
}

/// The subset of [VtracerConfig] that the auto-tuner is allowed to decide.
///
/// The model output is validated field-by-field: unknown or out-of-range
/// values fall back to the heuristic baseline, and the final decision is
/// clamped before it ever reaches the pipeline.
class AiDecision {
  final Clustering clustering;
  final Hierarchical hierarchical;
  final FitMode fitMode;
  final int filterSpeckle;
  final int colorPrecision;
  final int layerDifference;
  final int cornerThreshold;
  final double lengthThreshold;
  final int spliceThreshold;
  final int? maxColors;
  final double? simplify;
  final int binaryThreshold;
  final bool binaryAdaptive;
  final int watershedDetail;

  /// Human-readable one-liner explaining the choice.
  final String rationale;

  /// Calibrated confidence (0..1) — from the model when available, scored
  /// from rule margins by the heuristic engine.
  final double confidence;

  final DecisionSource source;
  final TuningGoal goal;

  const AiDecision({
    required this.clustering,
    required this.hierarchical,
    required this.fitMode,
    required this.filterSpeckle,
    required this.colorPrecision,
    required this.layerDifference,
    required this.cornerThreshold,
    required this.lengthThreshold,
    required this.spliceThreshold,
    required this.maxColors,
    required this.simplify,
    required this.binaryThreshold,
    required this.binaryAdaptive,
    required this.watershedDetail,
    this.rationale = '',
    this.confidence = 0.5,
    this.source = DecisionSource.heuristic,
    this.goal = TuningGoal.balanced,
  });

  /// Capture a decision that reproduces `cfg` (used as the baseline for
  /// model outputs that omit fields).
  factory AiDecision.fromConfig(
    VtracerConfig cfg, {
    String rationale = 'current configuration',
    double confidence = 0.5,
    DecisionSource source = DecisionSource.heuristic,
    TuningGoal goal = TuningGoal.balanced,
  }) =>
      AiDecision(
        clustering: cfg.clustering,
        hierarchical: cfg.hierarchical,
        fitMode: cfg.mode,
        filterSpeckle: cfg.filterSpeckle,
        colorPrecision: cfg.colorPrecision,
        layerDifference: cfg.layerDifference,
        cornerThreshold: cfg.cornerThreshold,
        lengthThreshold: cfg.lengthThreshold,
        spliceThreshold: cfg.spliceThreshold,
        maxColors: cfg.maxColors,
        simplify: cfg.simplify,
        binaryThreshold: cfg.binaryThreshold,
        binaryAdaptive: cfg.binaryAdaptive,
        watershedDetail: cfg.watershedDetail,
        rationale: rationale,
        confidence: confidence,
        source: source,
        goal: goal,
      );

  /// Force every parameter back into the range the pipeline accepts.
  AiDecision clamped() {
    final clustering = this.clustering;
    final hierarchical = this.hierarchical;
    final fitMode = this.fitMode;
    final maxColors = this.maxColors;
    final simplify = this.simplify;
    return AiDecision(
      clustering: clustering,
      hierarchical: hierarchical,
      fitMode: fitMode,
      filterSpeckle: filterSpeckle.clamp(0, 128),
      colorPrecision: colorPrecision.clamp(1, 8),
      layerDifference: layerDifference.clamp(0, 255),
      cornerThreshold: cornerThreshold.clamp(0, 180),
      lengthThreshold: lengthThreshold.clamp(3.5, 10.0),
      spliceThreshold: spliceThreshold.clamp(0, 180),
      maxColors: maxColors?.clamp(2, 64),
      simplify: simplify == null
          ? null
          : simplify.clamp(0.1, 10.0).toDouble(),
      binaryThreshold: binaryThreshold.clamp(0, 255),
      binaryAdaptive: binaryAdaptive,
      watershedDetail: watershedDetail.clamp(16, 255),
      rationale: rationale,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      source: source,
      goal: goal,
    );
  }

  /// Mutate `cfg` in place to match this decision.
  void applyTo(VtracerConfig cfg) {
    cfg.clustering = clustering;
    cfg.hierarchical = hierarchical;
    cfg.mode = fitMode;
    cfg.filterSpeckle = filterSpeckle;
    cfg.colorPrecision = colorPrecision;
    cfg.layerDifference = layerDifference;
    cfg.cornerThreshold = cornerThreshold;
    cfg.lengthThreshold = lengthThreshold;
    cfg.spliceThreshold = spliceThreshold;
    cfg.maxColors = maxColors;
    cfg.simplify = simplify;
    cfg.binaryThreshold = binaryThreshold;
    cfg.binaryAdaptive = binaryAdaptive;
    cfg.watershedDetail = watershedDetail;
  }

  /// One-line parameter summary for logs / CLI output.
  String toSummary() =>
      'clustering=${_clusteringName} hierarchical=${_hierarchicalName} '
      'fit=${_fitName} speckle=$filterSpeckle precision=$colorPrecision '
      'gradient=$layerDifference max_colors=$maxColors simplify=$simplify '
      'confidence=${confidence.toStringAsFixed(2)}';

  Map<String, Object?> toJson() => {
        'clustering': _clusteringName,
        'hierarchical': _hierarchicalName,
        'fit_mode': _fitName,
        'filter_speckle': filterSpeckle,
        'color_precision': colorPrecision,
        'layer_difference': layerDifference,
        'corner_threshold': cornerThreshold,
        'segment_length': lengthThreshold,
        'splice_threshold': spliceThreshold,
        'max_colors': maxColors,
        'simplify': simplify,
        'binary_threshold': binaryThreshold,
        'binary_adaptive': binaryAdaptive,
        'watershed_detail': watershedDetail,
        'rationale': rationale,
        'confidence': confidence,
        'source': source.name,
        'goal': goal.name,
      };

  String get _clusteringName => switch (clustering) {
        Clustering.colorCluster => 'color-cluster',
        Clustering.binary => 'binary',
        Clustering.watershed => 'watershed',
      };

  String get _hierarchicalName => switch (hierarchical) {
        Hierarchical.stacked => 'stacked',
        Hierarchical.cutout => 'cutout',
      };

  String get _fitName => switch (fitMode) {
        FitMode.pixel => 'pixel',
        FitMode.polygon => 'polygon',
        FitMode.spline => 'spline',
      };
}
