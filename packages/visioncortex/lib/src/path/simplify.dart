import 'dart:math' as math;

import '../point.dart';
import 'paths.dart';
import 'util.dart';

enum PathSimplifyMode { none, polygon, spline }

class PathSimplify {
  /// Removes 1-pixel staircases, with an outset toward the given winding.
  static PathI32 removeStaircase(PathI32 path, bool clockwise) {
    final pts = path.path;
    final len = pts.length;

    int segmentLength(int i, int j) =>
        (pts[i].x - pts[j].x).abs() + (pts[i].y - pts[j].y).abs();

    final result = PathI32();
    if (len == 0) return result;
    for (var i = 0; i < len; i++) {
      final j = (i + 1) % len;
      final h = i > 0 ? i - 1 : len - 1;
      var keep = true;
      if (i != 0 && i != len - 1) {
        if (segmentLength(i, h) == 1 || segmentLength(i, j) == 1) {
          final area = signedAreaI32(pts[h], pts[i], pts[j]);
          keep = area != 0 && (area > 0) == clockwise;
        }
      }
      if (keep) {
        result.add(pts[i].clone());
      }
    }
    return result;
  }

  /// Symmetric (area-based) decimation: collapse vertex chains whose maximum
  /// triangle-area penalty stays below 1.0. Centered — no directional outset —
  /// so boundaries stay gapless (used by the mosaic fitter).
  static PathI32 limitPenalties(PathI32 path) {
    const tolerance = 1.0;
    final pts = path.path;
    final len = pts.length;

    final result = PathI32();
    if (len == 0) return result;
    var last = 0;
    for (var i = 0; i < len; i++) {
      if (i == 0) {
        result.add(pts[i].clone());
      } else if (i == last + 1) {
        continue;
      } else if (pastDelta(pts, last, i) >= tolerance) {
        last = i - 1;
        result.add(pts[i - 1].clone());
      }
      if (i == len - 1) {
        result.add(pts[i].clone());
      }
    }
    return result;
  }

  static double pastDelta(List<PointI32> pts, int from, int to) {
    var maxPenalty = 0.0;
    for (var i = from + 1; i < to; i++) {
      final p = evaluatePenalty(pts[from], pts[i], pts[to]);
      if (p > maxPenalty) maxPenalty = p;
    }
    return maxPenalty;
  }

  /// Square of the triangle area over the closing edge length.
  static double evaluatePenalty(PointI32 a, PointI32 b, PointI32 c) {
    final l1 = math.sqrt(_sq(a.x - b.x) + _sq(a.y - b.y));
    final l2 = math.sqrt(_sq(b.x - c.x) + _sq(b.y - c.y));
    final l3 = math.sqrt(_sq(c.x - a.x) + _sq(c.y - a.y));
    final p = (l1 + l2 + l3) / 2.0;
    final heron = p * (p - l1) * (p - l2) * (p - l3);
    final area = heron <= 0 ? 0.0 : math.sqrt(heron);
    final base = l3 == 0 ? 1e-30 : l3;
    return area * area / base;
  }

  static double _sq(int v) {
    final d = v.toDouble();
    return d * d;
  }
}
