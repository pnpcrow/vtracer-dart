import 'dart:math' as math;

import 'package:visioncortex/visioncortex.dart';

import 'colorfit.dart';
import 'compose.dart';
import 'fitter.dart';
import 'frontend/binary.dart';
import 'frontend/color_cluster.dart';
import 'frontend/frontend.dart';
import 'frontend/watershed.dart';
import 'mosaic/mosaic.dart';
import 'optimize.dart';
import 'pipeline.dart';
import 'simplify.dart';
import 'svg.dart';

/// Which region-forming algorithm segments the image.
enum Clustering {
  /// Hierarchical color clustering — the classic VTracer path.
  colorCluster,

  /// Threshold to black/white, then cluster the foreground.
  binary,

  /// Hierarchical watershed on the pixel graph, cut at `watershedDetail`.
  watershed;

  static Clustering? parse(String s) {
    switch (s) {
      case 'color-cluster':
      case 'colorcluster':
      case 'color':
        return Clustering.colorCluster;
      case 'binary':
      case 'bw':
      case 'BW':
        return Clustering.binary;
      case 'watershed':
        return Clustering.watershed;
      default:
        return null;
    }
  }
}

/// How regions are combined into the final document.
enum Hierarchical {
  /// Trace each layer independently and stack them in paint order.
  stacked,

  /// Seam-free, gapless mosaic: each shared boundary is fitted once and
  /// referenced by both adjacent faces.
  cutout;

  static Hierarchical? parse(String s) {
    switch (s) {
      case 'stacked':
        return Hierarchical.stacked;
      case 'cutout':
        return Hierarchical.cutout;
      default:
        return null;
    }
  }
}

/// How a region's pixel outline is turned into vector geometry.
enum FitMode {
  /// Exact pixel-lattice polyline; no smoothing.
  pixel,

  /// Douglas–Peucker polygon — straight edges, fewer points.
  polygon,

  /// Corner detection plus least-squares cubic Béziers — smooth curves.
  spline;

  static FitMode? parse(String s) {
    switch (s) {
      case 'pixel':
      case 'none':
        return FitMode.pixel;
      case 'polygon':
        return FitMode.polygon;
      case 'spline':
        return FitMode.spline;
      default:
        return null;
    }
  }
}

/// A starting point for [VtracerConfig], tuned for a common kind of input.
enum Preset {
  /// Black-and-white line art (binary clustering).
  bw,

  /// Flat, poster-like color with a fuller palette.
  poster,

  /// Photographic input: heavier speckle filtering and coarser layering.
  photo;

  static Preset? parse(String s) {
    switch (s) {
      case 'bw':
        return Preset.bw;
      case 'poster':
        return Preset.poster;
      case 'photo':
        return Preset.photo;
      default:
        return null;
    }
  }
}

/// The clustering-relevant projection of a [VtracerConfig]: two configs with
/// equal keys produce the same segmentation, so a cached one stays valid.
class SegmentKey {
  final Clustering clustering;
  final int colorPrecision;
  final int layerDifference;
  final int filterSpeckle;
  final int binaryThreshold;
  final bool binaryAdaptive;
  final int binaryAdaptiveWindow;
  final double binaryAdaptiveT;
  final int watershedDetail;

  const SegmentKey({
    required this.clustering,
    required this.colorPrecision,
    required this.layerDifference,
    required this.filterSpeckle,
    required this.binaryThreshold,
    required this.binaryAdaptive,
    required this.binaryAdaptiveWindow,
    required this.binaryAdaptiveT,
    required this.watershedDetail,
  });

  @override
  bool operator ==(Object other) =>
      other is SegmentKey &&
      clustering == other.clustering &&
      colorPrecision == other.colorPrecision &&
      layerDifference == other.layerDifference &&
      filterSpeckle == other.filterSpeckle &&
      binaryThreshold == other.binaryThreshold &&
      binaryAdaptive == other.binaryAdaptive &&
      binaryAdaptiveWindow == other.binaryAdaptiveWindow &&
      binaryAdaptiveT == other.binaryAdaptiveT &&
      watershedDetail == other.watershedDetail;

  @override
  int get hashCode => Object.hash(
        clustering,
        colorPrecision,
        layerDifference,
        filterSpeckle,
        binaryThreshold,
        binaryAdaptive,
        binaryAdaptiveWindow,
        binaryAdaptiveT,
        watershedDetail,
      );
}

/// High-level converter configuration; [build] turns it into a [Pipeline].
class VtracerConfig {
  /// Region-forming algorithm (see [Clustering]).
  Clustering clustering;

  /// How regions are combined — stacked layers or a seam-free mosaic.
  Hierarchical hierarchical;

  /// Speckle filter given as a side length; the area threshold is its square.
  int filterSpeckle;

  /// Significant bits per RGB channel (1..=8).
  int colorPrecision;

  /// Color difference between gradient layers.
  int layerDifference;

  /// Curve-fitting mode (see [FitMode]).
  FitMode mode;

  /// Corner threshold in degrees.
  int cornerThreshold;

  /// Segment length threshold in pixels.
  double lengthThreshold;

  /// Maximum least-squares refinement iterations per spline segment.
  int maxIterations;

  /// Splice threshold in degrees.
  int spliceThreshold;

  /// Curve simplification tolerance in px (paper.js-style `simplify`):
  /// re-fit smooth runs of fitted cubics with the fewest curves that stay
  /// within this distance, keeping corners in place. Null = off.
  double? simplify;

  /// Coordinate precision (decimal places) for output.
  int? pathPrecision;

  /// Fixed palette (empty = none). Takes priority over `maxColors`.
  List<Color> palette;

  /// Auto-quantize target color count (null = off).
  int? maxColors;

  /// Optimization level: 0 = off, 1 = quantize+cleanup, 2 = + shorthands.
  int optimize;

  /// Binary-mode fixed threshold (0..=255): foreground when grayscale
  /// intensity is below this. Ignored when `binaryAdaptive` is set.
  int binaryThreshold;

  /// Binary mode: use Bradley–Roth adaptive thresholding instead of the
  /// fixed cutoff (better for uneven lighting).
  bool binaryAdaptive;

  /// Adaptive window side length in pixels; 0 = auto.
  int binaryAdaptiveWindow;

  /// Adaptive sensitivity `t`: percent below the local mean (default 15).
  double binaryAdaptiveT;

  /// Watershed clustering: where to cut the hierarchy. Higher keeps more
  /// regions (each +25.5 roughly doubles the region count).
  int watershedDetail;

  VtracerConfig({
    this.clustering = Clustering.colorCluster,
    this.hierarchical = Hierarchical.stacked,
    this.filterSpeckle = 4,
    this.colorPrecision = 6,
    this.layerDifference = 16,
    this.mode = FitMode.spline,
    this.cornerThreshold = 60,
    this.lengthThreshold = 4.0,
    this.maxIterations = 10,
    this.spliceThreshold = 45,
    this.simplify,
    this.pathPrecision = 2,
    List<Color>? palette,
    this.maxColors,
    this.optimize = 1,
    this.binaryThreshold = 128,
    this.binaryAdaptive = false,
    this.binaryAdaptiveWindow = 0,
    this.binaryAdaptiveT = 15.0,
    this.watershedDetail = 128,
  }) : palette = palette ?? [];

  VtracerConfig.defaultConfig() : this();

  /// Build a config from a [Preset], adjusting the defaults for a common
  /// kind of input.
  factory VtracerConfig.fromPreset(Preset preset) {
    switch (preset) {
      case Preset.bw:
        return VtracerConfig(clustering: Clustering.binary);
      case Preset.poster:
        return VtracerConfig(colorPrecision: 8);
      case Preset.photo:
        return VtracerConfig(
          filterSpeckle: 10,
          colorPrecision: 8,
          layerDifference: 48,
          cornerThreshold: 180,
        );
    }
  }

  VtracerConfig clone() => VtracerConfig(
        clustering: clustering,
        hierarchical: hierarchical,
        filterSpeckle: filterSpeckle,
        colorPrecision: colorPrecision,
        layerDifference: layerDifference,
        mode: mode,
        cornerThreshold: cornerThreshold,
        lengthThreshold: lengthThreshold,
        maxIterations: maxIterations,
        spliceThreshold: spliceThreshold,
        simplify: simplify,
        pathPrecision: pathPrecision,
        palette: List.of(palette),
        maxColors: maxColors,
        optimize: optimize,
        binaryThreshold: binaryThreshold,
        binaryAdaptive: binaryAdaptive,
        binaryAdaptiveWindow: binaryAdaptiveWindow,
        binaryAdaptiveT: binaryAdaptiveT,
        watershedDetail: watershedDetail,
      );

  FitParams get _fitParams => FitParams(
        cornerThreshold: _deg2rad(cornerThreshold),
        lengthThreshold: lengthThreshold,
        maxIterations: maxIterations,
        spliceThreshold: _deg2rad(spliceThreshold),
      );

  Frontend _frontend() {
    switch (clustering) {
      case Clustering.colorCluster:
        return ColorClusterFrontend(
          colorPrecisionLoss: 8 - colorPrecision,
          layerDifference: layerDifference,
          goodMinArea: speckleArea(),
        );
      case Clustering.binary:
        final threshold = binaryAdaptive
            ? AdaptiveThreshold(binaryAdaptiveWindow, binaryAdaptiveT)
            : FixedThreshold(binaryThreshold);
        return BinaryFrontend(
          threshold: threshold,
          diagonal: false,
          minArea: speckleArea(),
        );
      case Clustering.watershed:
        return WatershedFrontend(
          detail: watershedDetail,
          minArea: speckleArea(),
        );
    }
  }

  /// Speckle filter area (px), fed to the frontend.
  int speckleArea() => filterSpeckle * filterSpeckle;

  List<ColorFitter> _colorFitters() {
    if (palette.isNotEmpty) {
      return [FixedPalette(List.of(palette)), const MergeAdjacent()];
    } else if (maxColors != null) {
      return [AutoQuantize(maxColors: maxColors!), const MergeAdjacent()];
    }
    return [const Identity()];
  }

  CurveFitter _fitter() {
    switch (mode) {
      case FitMode.pixel:
        return const PixelFitter();
      case FitMode.polygon:
        return const PolygonFitter();
      case FitMode.spline:
        return SplineFitter(_fitParams);
    }
  }

  SegmentFitter _segmentFitter() {
    switch (mode) {
      case FitMode.pixel:
        return const PixelSegmentFitter();
      case FitMode.polygon:
        return const PolygonSegmentFitter();
      case FitMode.spline:
        return SplineSegmentFitter(
          cornerThreshold: _deg2rad(cornerThreshold),
          lengthThreshold: lengthThreshold,
          maxIterations: maxIterations,
          spliceThreshold: _deg2rad(spliceThreshold),
        );
    }
  }

  List<CurvePass> _curvePasses() {
    if (simplify != null && simplify! > 0.0) {
      return [
        SimplifyCurves(tolerance: simplify!, cornerThreshold: _deg2rad(cornerThreshold)),
      ];
    }
    return [];
  }

  List<OptimizerPass> _optimizers() {
    if (optimize == 0) {
      return [];
    }
    final precision = pathPrecision ?? 2;
    return [QuantizePass(precision), const CleanupPass()];
  }

  SvgWriter _writer() {
    switch (optimize) {
      case 0:
        return SvgWriter(relative: false, shorthands: false, precision: pathPrecision);
      case 1:
        return SvgWriter(relative: true, shorthands: false, precision: pathPrecision);
      default:
        return SvgWriter(relative: true, shorthands: true, precision: pathPrecision);
    }
  }

  /// The clustering-relevant subset of this config — what [Session] compares
  /// to decide whether to re-segment.
  SegmentKey segmentKey() => SegmentKey(
        clustering: clustering,
        colorPrecision: colorPrecision,
        layerDifference: layerDifference,
        filterSpeckle: filterSpeckle,
        binaryThreshold: binaryThreshold,
        binaryAdaptive: binaryAdaptive,
        binaryAdaptiveWindow: binaryAdaptiveWindow,
        binaryAdaptiveT: binaryAdaptiveT,
        watershedDetail: watershedDetail,
      );

  /// Assemble a concrete pipeline from this configuration.
  Pipeline build() {
    final Compositing compositing;
    switch (hierarchical) {
      case Hierarchical.stacked:
        compositing = StackedCompositing(_fitter());
      case Hierarchical.cutout:
        // Rejoin flattened neighbours the clustering split too finely.
        final mergeDiff = clustering == Clustering.watershed
            ? ((255 - watershedDetail) ~/ 8).clamp(2, 1 << 30)
            : layerDifference;
        compositing = MosaicCompositing(_segmentFitter(), mergeDiff);
    }

    return Pipeline(
      frontend: _frontend(),
      colorFitters: _colorFitters(),
      compositing: compositing,
      curvePasses: _curvePasses(),
      optimizers: _optimizers(),
      writer: _writer(),
    );
  }
}

double _deg2rad(int deg) => deg / 180.0 * math.pi;
