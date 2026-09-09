import 'dart:math' as math;

import '../point.dart';

/// assume origin is top left corner, signed_area > 0 imply clockwise
int signedAreaI32(PointI32 p1, PointI32 p2, PointI32 p3) =>
    (p2.x - p1.x) * (p3.y - p1.y) - (p3.x - p1.x) * (p2.y - p1.y);

class Intersection {
  /// The relative location between (p1, p2). 0 means p1, 1 means p2.
  final double mua;

  /// The relative location between (p3, p4). 0 means p3, 1 means p4.
  final double mub;

  const Intersection(this.mua, this.mub);

  bool get coincide => mua.isNaN && mub.isNaN;
}

/// Intersection of lines (p1, p2) and (p3, p4). Coincident lines return the
/// midpoint of (p1, p2) with a NaN-parameter [Intersection]; parallel lines
/// return `null`.
(PointF64, Intersection)? findIntersection(
    PointF64 p1, PointF64 p2, PointF64 p3, PointF64 p4) {
  final denom = (p4.y - p3.y) * (p2.x - p1.x) - (p4.x - p3.x) * (p2.y - p1.y);
  final numera = (p4.x - p3.x) * (p1.y - p3.y) - (p4.y - p3.y) * (p1.x - p3.x);
  final numerb = (p2.x - p1.x) * (p1.y - p3.y) - (p2.y - p1.y) * (p1.x - p3.x);

  if (_negligible(denom) && _negligible(numera) && _negligible(numerb)) {
    return (findMidPoint(p1, p2), const Intersection(double.nan, double.nan));
  }

  if (_negligible(denom)) {
    return null;
  }

  final mua = numera / denom;
  final mub = numerb / denom;

  return (
    PointF64(p1.x + mua * (p2.x - p1.x), p1.y + mua * (p2.y - p1.y)),
    Intersection(mua, mub),
  );
}

bool _negligible(double v) => -1e-7 < v && v < 1e-7;

PointF64 findMidPoint(PointF64 p1, PointF64 p2) =>
    PointF64((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);

double normF64(PointF64 p) => math.sqrt(p.x * p.x + p.y * p.y);

PointF64 normalizeF64(PointF64 p) {
  final n = normF64(p);
  return PointF64(p.x / n, p.y / n);
}

/// Angle of a vector in [0, π] mirrored to (-π, 0] for negative y — i.e. the
/// standard atan2-style angle in (-π, π].
double angleOf(PointF64 p) {
  if (p.y.isNegative) {
    return -math.acos(p.x.clamp(-1.0, 1.0));
  }
  return math.acos(p.x.clamp(-1.0, 1.0));
}

/// Given angles in (-pi,pi], find the signed angle difference.
/// Positive in clockwise direction, 0-degree axis is the positive x axis.
double signedAngleDifference(double from, double to) {
  final v1 = from;
  var v2 = to;
  if (v1 > v2) {
    v2 += 2.0 * math.pi;
  }
  final diff = v2 - v1;
  if (diff > math.pi) {
    return diff - 2.0 * math.pi;
  }
  return diff;
}
