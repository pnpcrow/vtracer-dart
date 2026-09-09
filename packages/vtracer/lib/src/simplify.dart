import 'dart:math' as math;

import 'package:visioncortex/visioncortex.dart';

import 'fitter.dart';
import 'flo_access.dart';

/// A geometry pass over one fitted contour, run between curve fitting and
/// composition. Implementations must keep an open chain's endpoints exactly
/// (mosaic junction nodes must not move) and keep a ring closed.
abstract class CurvePass {
  /// Transform an open chain; both endpoints are pinned.
  FittedGeom open(FittedGeom geom);

  /// Transform a closed ring.
  FittedGeom ring(FittedGeom geom);
}

/// paper.js-style curve simplification (Schneider's fit): re-fit each smooth
/// run of cubics between corners with the fewest curves that stay within
/// `tolerance` of the fitted geometry.
class SimplifyCurves implements CurvePass {
  /// Maximum distance (px) the simplified curve may stray from the fitted
  /// one. paper.js defaults to 2.5.
  final double tolerance;

  /// Tangent-break angle (radians) above which an anchor is a corner and
  /// must survive in place; runs are re-fitted between corners.
  final double cornerThreshold;

  const SimplifyCurves({required this.tolerance, required this.cornerThreshold});

  @override
  FittedGeom open(FittedGeom geom) {
    switch (geom) {
      case FittedBeziers(:final curves):
        return FittedBeziers(_simplifyChain(curves, false));
      default:
        return geom;
    }
  }

  @override
  FittedGeom ring(FittedGeom geom) {
    switch (geom) {
      case FittedBeziers(:final curves):
        return FittedBeziers(_simplifyChain(curves, true));
      default:
        return geom;
    }
  }

  List<List<PointF64>> _simplifyChain(List<List<PointF64>> chain, bool closed) {
    if (tolerance <= 0.0 || chain.length < 2) {
      return chain;
    }

    var work = chain;
    if (closed) {
      // The re-fit pins run endpoints, so a ring needs a seam. Put it at the
      // sharpest junction (wraparound included).
      final angles = List<double>.generate(work.length, (k) {
        final prev = k == 0 ? work.length - 1 : k - 1;
        return _breakAngle(work[prev], work[k]);
      });
      var seam = 0;
      var bestAngle = angles[0];
      for (var i = 1; i < angles.length; i++) {
        if (angles[i] > bestAngle) {
          bestAngle = angles[i];
          seam = i;
        }
      }
      work = [...work.skip(seam), ...work.take(seam)];
    }

    // Cut into smooth runs at corner anchors (chain ends are always cuts).
    final cuts = <int>[0];
    for (var i = 1; i < work.length; i++) {
      if (_breakAngle(work[i - 1], work[i]) >= cornerThreshold) {
        cuts.add(i);
      }
    }
    cuts.add(work.length);

    final out = <List<PointF64>>[];
    for (var w = 0; w + 1 < cuts.length; w++) {
      final run = work.sublist(cuts[w], cuts[w + 1]);
      if (run.length < 2) {
        out.addAll(run);
        continue;
      }
      final refit = _refitRun(run, tolerance);
      if (refit != null && refit.length < run.length) {
        out.addAll(refit);
      } else {
        out.addAll(run);
      }
    }
    return out;
  }
}

/// Schneider-fit one smooth run: sample it, then fit with the run's own end
/// tangents (`endTangent` points backward, per the fit's contract). Returns
/// null for degenerate (point-like) runs.
List<List<PointF64>>? _refitRun(List<List<PointF64>> run, double tolerance) {
  final startTan = _tangentOut(run.first);
  final endTan = _tangentIn(run.last);
  if (startTan == null || endTan == null) {
    return null;
  }
  final samples = _sampleRun(run, tolerance);

  final fitted = fitCurveCubicAccess(
    samples,
    PointF64(startTan.$1, startTan.$2),
    PointF64(-endTan.$1, -endTan.$2),
    tolerance,
  );
  if (fitted.isEmpty) {
    return null;
  }

  final out = fitted
      .map((c) => [c.$1.clone(), c.$2.clone(), c.$3.clone(), c.$4.clone()])
      .toList();
  out.first[0] = run[0][0].clone();
  out.last[3] = run[run.length - 1][3].clone();
  return out;
}

double _dist(PointF64 a, PointF64 b) => math.sqrt(
    (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

/// Unit direction a→b, or null when the points (nearly) coincide.
(double, double)? _dir(PointF64 a, PointF64 b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1e-9) {
    return null;
  }
  return (dx / len, dy / len);
}

/// Tangent arriving at a cubic's end: the last distinct control point wins.
(double, double)? _tangentIn(List<PointF64> c) =>
    _dir(c[2], c[3]) ?? _dir(c[1], c[3]) ?? _dir(c[0], c[3]);

/// Tangent leaving a cubic's start: the first distinct control point wins.
(double, double)? _tangentOut(List<PointF64> c) =>
    _dir(c[0], c[1]) ?? _dir(c[0], c[2]) ?? _dir(c[0], c[3]);

/// Turn angle at the junction of two consecutive cubics. A fully degenerate
/// (point-like) neighbour counts as a corner so it is never smoothed across.
double _breakAngle(List<PointF64> prev, List<PointF64> next) {
  final a = _tangentIn(prev);
  final b = _tangentOut(next);
  if (a != null && b != null) {
    return math.acos((a.$1 * b.$1 + a.$2 * b.$2).clamp(-1.0, 1.0));
  }
  return math.pi;
}

PointF64 _cubicAt(List<PointF64> c, double t) {
  final u = 1.0 - t;
  final b0 = u * u * u;
  final b1 = 3.0 * u * u * t;
  final b2 = 3.0 * u * t * t;
  final b3 = t * t * t;
  return PointF64(
    b0 * c[0].x + b1 * c[1].x + b2 * c[2].x + b3 * c[3].x,
    b0 * c[0].y + b1 * c[1].y + b2 * c[2].y + b3 * c[3].y,
  );
}

/// Sample a run of cubics at roughly 1 px spacing (by control-polygon
/// length), tighter when the tolerance is sub-pixel. The first and last
/// samples are the run's endpoints, exactly.
List<PointF64> _sampleRun(List<List<PointF64>> run, double tolerance) {
  final spacing = tolerance.clamp(0.25, 1.0);
  final samples = <PointF64>[run[0][0].clone()];
  for (final c in run) {
    final len = _dist(c[0], c[1]) + _dist(c[1], c[2]) + _dist(c[2], c[3]);
    final n = (len / spacing).ceil().clamp(1, 512);
    for (var k = 1; k <= n; k++) {
      samples.add(_cubicAt(c, k / n));
    }
  }
  return samples;
}
