import '../point.dart';
import '../flo/fit.dart' as flo;
import 'paths.dart';
import 'util.dart';

/// Handles path smoothing: corner detection, splice points, 4-point
/// subdivision and cubic fitting.
///
/// Every routine takes a `closed` flag. Closed paths (walked polygons) assume
/// the last point repeats the first and index with wraparound. Open paths keep
/// every point, never wrap, and force both endpoints as corners / splice
/// points so that pinned endpoints (e.g. mosaic junction nodes) survive
/// fitting.
class SubdivideSmooth {
  /// Corners of an integer path (angle in radians >= threshold).
  static List<bool> findCornersI32(PathI32 path, double threshold, bool closed) {
    final pts = closed ? path.path.sublist(0, path.path.length - 1) : path.path;
    final len = pts.length;
    if (len == 0) return [];

    final corners = List<bool>.filled(len, false);
    for (var i = 0; i < len; i++) {
      if (!closed && (i == 0 || i == len - 1)) {
        corners[i] = true; // endpoints pinned as corners
        continue;
      }
      final prev = i == 0 ? len - 1 : i - 1;
      final next = (i + 1) % len;

      final v1 = PointF64(
          (pts[i].x - pts[prev].x).toDouble(), (pts[i].y - pts[prev].y).toDouble());
      final v2 = PointF64(
          (pts[next].x - pts[i].x).toDouble(), (pts[next].y - pts[i].y).toDouble());

      final angleV1 = angleOf(normalizeF64(v1));
      final angleV2 = angleOf(normalizeF64(v2));

      final angleDiff = signedAngleDifference(angleV1, angleV2).abs();
      if (angleDiff >= threshold) {
        corners[i] = true;
      }
    }
    return corners;
  }

  /// Splice points of a smoothed path (angle displacement in radians
  /// >= threshold).
  static List<bool> findSplicePoints(PathF64 path, double threshold, bool closed) {
    final pts = closed ? path.path.sublist(0, path.path.length - 1) : path.path;
    final len = pts.length;
    if (len == 0) return [];

    final splicePoints = List<bool>.filled(len, false);
    var isAngleIncreasing = false;
    var started = false;
    var angleDisp = 0.0;
    for (var i = 0; i < len; i++) {
      if (!closed && (i == 0 || i == len - 1)) {
        splicePoints[i] = true; // endpoints pinned as splice points
        angleDisp = 0.0;
        continue;
      }
      final prev = i == 0 ? len - 1 : i - 1;
      final next = (i + 1) % len;

      final v1 = pts[i] - pts[prev];
      final v2 = pts[next] - pts[i];

      final angleV1 = angleOf(normalizeF64(v1));
      final angleV2 = angleOf(normalizeF64(v2));

      final angleDiff = signedAngleDifference(angleV1, angleV2);
      // Rust is_sign_positive(): true for +0.0 and positives.
      final isCurrentlyIncreasing = !angleDiff.isNegative;

      if (!started) {
        isAngleIncreasing = isCurrentlyIncreasing;
        started = true;
      } else if (isAngleIncreasing != isCurrentlyIncreasing) {
        splicePoints[i] = true;
        isAngleIncreasing = isCurrentlyIncreasing;
      }

      angleDisp += angleDiff;
      if (angleDisp.abs() >= threshold) {
        splicePoints[i] = true;
      }

      if (splicePoints[i]) {
        angleDisp = 0.0;
      }
    }
    return splicePoints;
  }

  /// Single-curve fit of a point slice (Schneider). Truncates to one curve.
  static List<PointF64> fitPointsWithBezier(List<PointF64> points, double maxError) {
    final curves = flo.CurveFit.fitCurve(points, maxError);
    if (curves == null || curves.isEmpty) {
      return [PointF64.zero(), PointF64.zero(), PointF64.zero(), PointF64.zero()];
    }
    final curve = curves[0];
    final p1 = points[0];
    final p4 = points[points.length - 1];
    final p2 = curve.$2;
    final p3 = curve.$3;
    return retractHandles(p1, p2, p3, p4);
  }

  /// Insert evenly spaced witness points along any segment longer than
  /// `spacing`, so the fit's error metric cannot miss a deviation between two
  /// far-apart samples.
  static List<PointF64> densify(List<PointF64> points, double spacing) {
    final out = <PointF64>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      out.add(a);
      final d = normF64(b - a);
      final n = (d / spacing).ceil();
      for (var k = 1; k < n; k++) {
        final t = k / n;
        out.add(PointF64(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
      }
    }
    out.add(points[points.length - 1]);
    return out;
  }

  /// The full chain of cubic Béziers approximating `points` within
  /// `maxError` — one `[start, ctrl1, ctrl2, end]` per curve, sharing
  /// endpoints, outer endpoints pinned to the input. Falls back to a straight
  /// segment when the fit fails outright.
  static List<List<PointF64>> fitPointsWithBeziers(
      List<PointF64> points, double maxError) {
    final p1 = points[0];
    final p4 = points[points.length - 1];
    List<List<PointF64>> straight() => [
          [p1.clone(), p1.clone(), p4.clone(), p4.clone()]
        ];

    if (points.length < 2) return straight();

    final dense = densify(points, maxError);
    final curves = flo.CurveFit.fitCurve(dense, maxError);
    if (curves == null || curves.isEmpty) {
      return straight();
    }

    // The fit's fragments do not share endpoints exactly — weld each pair at
    // their midpoint, and pin the outer endpoints to the input.
    final raw = curves
        .map((c) => [c.$1.clone(), c.$2.clone(), c.$3.clone(), c.$4.clone()])
        .toList();
    final last = raw.length - 1;
    raw[0][0] = p1.clone();
    raw[last][3] = p4.clone();
    for (var i = 1; i < raw.length; i++) {
      final shared = findMidPoint(raw[i - 1][3], raw[i][0]);
      raw[i - 1][3] = shared.clone();
      raw[i][0] = shared.clone();
    }
    return raw.map((c) => retractHandles(c[0], c[1], c[2], c[3])).toList();
  }

  /// 4-point scheme subdivision keeping corners. Returns the new path, updated
  /// corner flags, and whether no further subdivision is needed.
  static (PathF64, List<bool>, bool) subdivideKeepCorners(
      PathF64 path, List<bool> corners, double outsetRatio, double segmentLength,
      bool closed) {
    final pts = closed ? path.path.sublist(0, path.path.length - 1) : path.path;
    final len = pts.length;

    var canTerminateIteration = true;

    final newPath = <PointF64>[];
    final newCorners = <bool>[];

    for (var i = 0; i < len; i++) {
      newPath.add(PointF64(pts[i].x, pts[i].y));
      newCorners.add(corners[i]);

      // Open paths have no segment leaving the last vertex.
      if (!closed && i == len - 1) {
        continue;
      }
      final j = closed ? (i + 1) % len : i + 1;

      // Length threshold on the current segment.
      final lengthCurr = normF64(pts[i] - pts[j]);
      if (lengthCurr <= segmentLength) {
        continue;
      }

      var prev = closed ? (i == 0 ? len - 1 : i - 1) : (i == 0 ? i : i - 1);
      var next = closed ? (j + 1) % len : (j == len - 1 ? j : j + 1);

      // Check ratio of adjacent segments.
      final lengthPrev = normF64(pts[prev] - pts[i]);
      final lengthNext = normF64(pts[next] - pts[j]);
      if (lengthPrev / lengthCurr >= 2.0 || lengthNext / lengthCurr >= 2.0) {
        continue;
      }

      // Switch to 3-point scheme to preserve corners.
      if (corners[i]) prev = i;
      if (corners[j]) next = j;

      if (prev == i && next == j) {
        continue; // two corners are neighbors
      }
      final newPoint =
          _findNewPointFrom4PointScheme(pts[i], pts[j], pts[prev], pts[next], outsetRatio);
      newPath.add(newPoint);
      newCorners.add(false);
      if (normF64(pts[i] - newPoint) > segmentLength ||
          normF64(pts[j] - newPoint) > segmentLength) {
        canTerminateIteration = false;
      }
    }

    if (closed) {
      newPath.add(newPath[0].clone());
    }

    return (PathF64.fromPoints(newPath), newCorners, canTerminateIteration);
  }

  static PointF64 _findNewPointFrom4PointScheme(
      PointF64 pi, PointF64 pj, PointF64 p1, PointF64 p2, double outsetRatio) {
    final midOut = findMidPoint(pi, pj);
    final midIn = findMidPoint(p1, p2);

    final vectorOut = midOut - midIn;
    final newMagnitude = vectorOut.norm() / outsetRatio;
    if (newMagnitude < 2.220446049250313e-16) {
      return midOut;
    }

    return midOut + vectorOut.normalized() * newMagnitude;
  }

  /// Pulls control points back to the chord when the handles cross it,
  /// preventing loops in the fitted cubic.
  static List<PointF64> retractHandles(
      PointF64 a, PointF64 b, PointF64 c, PointF64 d) {
    final da = a - d;
    final ab = b - a;
    final dab = signedAngleDifference(angleOf(normalizeF64(da)), angleOf(normalizeF64(ab)));

    final bc = c - b;
    final abc = signedAngleDifference(angleOf(normalizeF64(ab)), angleOf(normalizeF64(bc)));

    final dabPositive = !dab.isNegative;
    final abcPositive = !abc.isNegative;

    if (dabPositive != abcPositive) {
      final hit = findIntersection(a, b, c, d);
      if (hit != null) {
        final intersection = hit.$1;
        return [a.clone(), intersection.clone(), intersection.clone(), d.clone()];
      }
    }
    return [a.clone(), b.clone(), c.clone(), d.clone()];
  }
}
