part of 'mosaic.dart';

/// Outset ratio for the 4-point subdivision scheme (matches visioncortex).
const double _outsetRatio = 8.0;

/// Error bound for the per-slice cubic fit — matches the stacked mode value.
const double _fitError = 10.0;

/// A fitted segment, cached and indexed by segment id.
class FittedSegment {
  FittedGeom geom;
  FittedSegment(this.geom);
}

/// Fits a single boundary segment. `fitOpen` pins both endpoints (junction
/// nodes must not move); `fitRing` fits a closed loop with no pinned point.
abstract class SegmentFitter {
  FittedSegment fitOpen(Segment seg);
  FittedSegment fitRing(Segment seg);
}

List<PointF64> _toF64(List<PointI32> points) =>
    points.map((p) => PointF64(p.x.toDouble(), p.y.toDouble())).toList();

PointF64 _pt(PointI32 p) => PointF64(p.x.toDouble(), p.y.toDouble());

/// Identity fitter: lattice points as f64. Produces an exact tessellation.
class PixelSegmentFitter implements SegmentFitter {
  const PixelSegmentFitter();

  @override
  FittedSegment fitOpen(Segment seg) => FittedSegment(FittedPolyline(_toF64(seg.points)));

  @override
  FittedSegment fitRing(Segment seg) => FittedSegment(FittedPolyline(_toF64(seg.points)));
}

/// Straight-segment fitter via the symmetric `limit_penalties`
/// simplification, which collapses 1px staircases toward the crack midline so
/// the boundary stays gapless. Endpoints are preserved.
class PolygonSegmentFitter implements SegmentFitter {
  const PolygonSegmentFitter();

  FittedSegment _fit(Segment seg) {
    final simplified =
        PathSimplify.limitPenalties(PathI32.fromPoints(_clonePoints(seg.points)));
    return FittedSegment(FittedPolyline(simplified.path.map(_pt).toList()));
  }

  @override
  FittedSegment fitOpen(Segment seg) => _fit(seg);

  @override
  FittedSegment fitRing(Segment seg) => _fit(seg);
}

List<PointI32> _clonePoints(List<PointI32> pts) =>
    pts.map((p) => p.clone()).toList();

/// A degenerate cubic tracing the straight line a→b.
List<PointF64> _straightCubic(PointF64 a, PointF64 b) {
  final c1 = PointF64(a.x + (b.x - a.x) / 3.0, a.y + (b.y - a.y) / 3.0);
  final c2 = PointF64(a.x + 2.0 * (b.x - a.x) / 3.0, a.y + 2.0 * (b.y - a.y) / 3.0);
  return [a.clone(), c1, c2, b.clone()];
}

/// Fit one splice slice with the full retract-handled cubic chain per slice,
/// outer endpoints pinned to the slice ends.
void _fitSlice(List<PointF64> slice, List<List<PointF64>> out) {
  switch (slice.length) {
    case 0:
    case 1:
      break;
    case 2:
      out.add(_straightCubic(slice[0], slice[1]));
      break;
    default:
      out.addAll(SubdivideSmooth.fitPointsWithBeziers(slice, _fitError));
  }
}

List<List<PointF64>> _splineToBeziers(Spline spline) {
  // Spline curves of exactly 4 control points each.
  final out = <List<PointF64>>[];
  final pts = spline.points;
  for (var i = 0; i + 3 < pts.length; i += 3) {
    out.add([
      pts[i].clone(),
      pts[i + 1].clone(),
      pts[i + 2].clone(),
      pts[i + 3].clone(),
    ]);
  }
  return out;
}

/// Smooth (cubic-Bézier) open-path fitter — the mosaic analogue of the
/// stacked spline fitter, for open segments with pinned endpoints.
class SplineSegmentFitter implements SegmentFitter {
  /// Corner angle threshold, radians.
  final double cornerThreshold;

  /// Subdivide until segments are shorter than this (px).
  final double lengthThreshold;
  final int maxIterations;

  /// Splice angle threshold, radians.
  final double spliceThreshold;

  const SplineSegmentFitter({
    this.cornerThreshold = 1.0471975511965976,
    this.lengthThreshold = 4.0,
    this.maxIterations = 10,
    this.spliceThreshold = 0.7853981633974483,
  });

  @override
  FittedSegment fitOpen(Segment seg) {
    if (seg.points.length <= 2) {
      return FittedSegment(FittedPolyline(_toF64(seg.points)));
    }

    // 1. Staircase removal via symmetric limit-penalties simplification:
    //    endpoints preserved, boundary stays centered and gapless.
    final simplified =
        PathSimplify.limitPenalties(PathI32.fromPoints(_clonePoints(seg.points)));
    if (simplified.length <= 2) {
      return FittedSegment(FittedPolyline(simplified.path.map(_pt).toList()));
    }

    // 2. Corner detection (open, endpoints forced as corners).
    var corners = SubdivideSmooth.findCornersI32(simplified, cornerThreshold, false);
    // 3. Open 4-point subdivision.
    var path = simplified.toPathF64();
    for (var i = 0; i < maxIterations; i++) {
      final (np, nc, done) = SubdivideSmooth.subdivideKeepCorners(
          path, corners, _outsetRatio, lengthThreshold, false);
      path = np;
      corners = nc;
      if (done) {
        break;
      }
    }
    // 4. Splice points (open, endpoints forced).
    final splice = SubdivideSmooth.findSplicePoints(path, spliceThreshold, false);
    final cuts = <int>[
      for (var i = 0; i < splice.length; i++)
        if (splice[i]) i
    ];

    // 5. Per-slice cubic fit.
    final beziers = <List<PointF64>>[];
    for (var w = 0; w + 1 < cuts.length; w++) {
      _fitSlice(path.path.sublist(cuts[w], cuts[w + 1] + 1), beziers);
    }

    if (beziers.isEmpty) {
      return FittedSegment(FittedPolyline(path.path.map((p) => p.clone()).toList()));
    }

    // Pin the segment's endpoints exactly to the lattice nodes.
    beziers.first[0] = _pt(seg.points[0]);
    beziers.last[3] = _pt(seg.points[seg.points.length - 1]);

    return FittedSegment(FittedBeziers(beziers));
  }

  @override
  FittedSegment fitRing(Segment seg) {
    // Rings are closed loops — exactly the stacked closed-spline pipeline.
    if (seg.points.length <= 4) {
      return FittedSegment(FittedPolyline(_toF64(seg.points)));
    }
    final simplified =
        PathSimplify.limitPenalties(PathI32.fromPoints(_clonePoints(seg.points)));
    final smoothed =
        simplified.smoothed(cornerThreshold, _outsetRatio, lengthThreshold, maxIterations);
    final spline = Spline.fromPathF64(smoothed, spliceThreshold);
    final beziers = _splineToBeziers(spline);
    if (beziers.isEmpty) {
      return FittedSegment(FittedPolyline(_toF64(seg.points)));
    }
    return FittedSegment(FittedBeziers(beziers));
  }
}
