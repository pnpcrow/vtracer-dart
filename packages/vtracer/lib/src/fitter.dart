import 'package:visioncortex/visioncortex.dart';

import 'ir.dart';

/// Fitted geometry for one contour — the common currency between the curve
/// fitters, the curve-pass stage, and composition.
sealed class FittedGeom {}

/// Polyline (pixel / polygon backends).
class FittedPolyline extends FittedGeom {
  List<PointF64> points;
  FittedPolyline(this.points);
}

/// Chain of cubic Béziers; consecutive curves share endpoints.
class FittedBeziers extends FittedGeom {
  List<List<PointF64>> curves;
  FittedBeziers(this.curves);
}

extension FittedGeomConvert on FittedGeom {
  /// Convert one closed contour into a `MoveTo … Close` subpath.
  SubPath intoClosedSubpath() {
    switch (this) {
      case FittedPolyline(:final points):
        return polylineSubpath(points);
      case FittedBeziers(:final curves):
        return beziersSubpath(curves);
    }
  }
}

/// Fitting parameters shared by the built-in fitters.
class FitParams {
  /// Minimum momentary angle (radians) to be considered a corner.
  final double cornerThreshold;

  /// Subdivide until all segments are shorter than this length (px).
  final double lengthThreshold;

  /// Maximum smoothing iterations.
  final int maxIterations;

  /// Minimum angle displacement (radians) to splice a spline.
  final double spliceThreshold;

  const FitParams({
    this.cornerThreshold = 1.0471975511965976, // 60°
    this.lengthThreshold = 4.0,
    this.maxIterations = 10,
    this.spliceThreshold = 0.7853981633974483, // 45°
  });
}

/// A curve fitter traces a region mask into closed vector outlines, one
/// [FittedGeom] per contour (outer ring or hole).
abstract class CurveFitter {
  List<FittedGeom> fitRegion(RegionMask mask);
}

/// Exact lattice polyline; every pixel-boundary step is preserved.
class PixelFitter implements CurveFitter {
  const PixelFitter();

  @override
  List<FittedGeom> fitRegion(RegionMask mask) =>
      _traceRegion(mask, PathSimplifyMode.none, const FitParams());
}

/// Douglas–Peucker polygon with staircase removal.
class PolygonFitter implements CurveFitter {
  const PolygonFitter();

  @override
  List<FittedGeom> fitRegion(RegionMask mask) =>
      _traceRegion(mask, PathSimplifyMode.polygon, const FitParams());
}

/// Smoothed spline (cubic Bézier) fitter.
class SplineFitter implements CurveFitter {
  final FitParams params;

  const SplineFitter(this.params);

  @override
  List<FittedGeom> fitRegion(RegionMask mask) =>
      _traceRegion(mask, PathSimplifyMode.spline, params);
}

/// Trace every connected component of a masked region and collect the
/// resulting outlines in absolute coordinates.
List<FittedGeom> _traceRegion(
    RegionMask mask, PathSimplifyMode mode, FitParams params) {
  final geoms = <FittedGeom>[];
  for (final sub in mask.image.toClusters(false).clusters) {
    final offset = PointI32(
      mask.offset.x + sub.rect.left,
      mask.offset.y + sub.rect.top,
    );
    final compound = BinaryCluster.imageToCompoundPath(
      offset,
      sub.toBinaryImage(),
      mode,
      params.cornerThreshold,
      params.lengthThreshold,
      params.maxIterations,
      params.spliceThreshold,
    );
    _appendCompound(geoms, compound);
  }
  return geoms;
}

void _appendCompound(List<FittedGeom> geoms, CompoundPath compound) {
  for (final element in compound.elements) {
    switch (element) {
      case CompoundPathI32(:final path):
        geoms.add(FittedPolyline(
          path.path.map((q) => PointF64(q.x.toDouble(), q.y.toDouble())).toList(),
        ));
      case CompoundPathF64(:final path):
        geoms.add(FittedPolyline(path.path.map((p) => p.clone()).toList()));
      case CompoundPathSpline(:final spline):
        geoms.add(FittedBeziers(_splineChain(spline.points)));
    }
  }
}

/// A spline of `1 + 3n` points becomes a chain of `n` cubics sharing
/// endpoints.
List<List<PointF64>> _splineChain(List<PointF64> points) {
  if (points.length < 4 || (points.length - 1) % 3 != 0) {
    return [];
  }
  final chain = <List<PointF64>>[];
  var start = points[0].clone();
  var i = 1;
  while (i + 2 < points.length) {
    chain.add([start, points[i].clone(), points[i + 1].clone(), points[i + 2].clone()]);
    start = points[i + 2].clone();
    i += 3;
  }
  return chain;
}

/// A closed polyline whose last point repeats the first becomes
/// `MoveTo · LineTo* · Close`.
SubPath polylineSubpath(List<PointF64> points) {
  final sub = SubPath();
  if (points.length < 2) {
    return sub;
  }
  final closed = points.first == points.last;
  final bodyEnd = closed ? points.length - 1 : points.length;
  sub.commands.add(MoveTo(points[0].clone()));
  for (var i = 1; i < bodyEnd; i++) {
    sub.commands.add(LineTo(points[i].clone()));
  }
  sub.commands.add(const ClosePath());
  return sub;
}

/// A cubic chain becomes `MoveTo · CubicTo* · Close`.
SubPath beziersSubpath(List<List<PointF64>> chain) {
  final sub = SubPath();
  if (chain.isEmpty) {
    return sub;
  }
  sub.commands.add(MoveTo(chain[0][0].clone()));
  for (final c in chain) {
    sub.commands.add(CubicTo(c[1].clone(), c[2].clone(), c[3].clone()));
  }
  sub.commands.add(const ClosePath());
  return sub;
}
