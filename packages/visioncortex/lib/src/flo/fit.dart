import 'dart:math' as math;

import '../point.dart';

/// Schneider-style cubic Bézier fitting, ported from flo_curves
/// (`bezier::fit`): fit a chain of cubics to a point list within `maxError`.
///
/// `fitCurve` splits the input into blocks, derives end tangents from the
/// data, and calls [fitCurveCubic] (least-squares fit + Newton-Raphson
/// reparameterization + recursive subdivision at the worst point).
class CurveFit {
  /// Fits `points` with block splitting and data-derived tangents.
  /// Returns `null` when fewer than 2 points are given.
  static List<(PointF64, PointF64, PointF64, PointF64)>? fitCurve(
      List<PointF64> points, double maxError) {
    final maxPoints = _maxPointsToFit(points.length);

    if (points.length < 2) {
      return null;
    }

    final curves = <(PointF64, PointF64, PointF64, PointF64)>[];

    final numBlocks = ((points.length - 1) ~/ maxPoints) + 1;

    for (var block = 0; block < numBlocks; block++) {
      final startPointIdx = block * maxPoints;
      var numPoints = maxPoints;

      if (startPointIdx + numPoints > points.length) {
        numPoints = points.length - startPointIdx;
      }

      // Edge case: one point outside of a block (ignored).
      if (numPoints < 2) continue;

      final blockPoints = points.sublist(startPointIdx, startPointIdx + numPoints);

      final startTangent = _startTangent(blockPoints);
      final PointF64 endTangent;
      if (startPointIdx + numPoints + 1 < points.length) {
        endTangent =
            _endTangent(points.sublist(startPointIdx, startPointIdx + numPoints + 1));
      } else {
        endTangent = _endTangent(blockPoints);
      }

      final fit = fitCurveCubic(blockPoints, startTangent, endTangent, maxError);
      curves.addAll(fit);
    }

    return curves;
  }

  /// Fits a chain of cubics to `points` with the given unit end tangents.
  ///
  /// `startTangent` points along the curve at the start; `endTangent` points
  /// *backwards* (the direction the end control point protrudes from).
  static List<(PointF64, PointF64, PointF64, PointF64)> fitCurveCubic(
      List<PointF64> points, PointF64 startTangent, PointF64 endTangent,
      double maxError) {
    if (points.length <= 2) {
      return _fitLine(points[0], points[1]);
    }

    var chords = _chordsForPoints(points);
    var curve = _generateBezier(points, chords, startTangent, endTangent);

    chords = _reparameterize(points, chords, curve);
    curve = _generateBezier(points, chords, startTangent, endTangent);

    var (error, splitPos) = _maxErrorForCurve(points, chords, curve);

    if (error > maxError) {
      var lastError = error;
      for (var iteration = 1; iteration < maxIterations; iteration++) {
        chords = _reparameterize(points, chords, curve);
        curve = _generateBezier(points, chords, startTangent, endTangent);

        final (newError, newSplitPos) = _maxErrorForCurve(points, chords, curve);
        error = newError;
        splitPos = newSplitPos;

        final improvement = error / lastError;
        if (improvement > 0.95) break;
        if (error <= maxError) break;

        lastError = error;
      }
    }

    if (error <= maxError) {
      return [curve];
    }

    // Error still too large: split at the worst point and fit both sides.
    final centerTangent = _tangentBetween(
        points[splitPos - 1], points[splitPos], points[splitPos + 1]);

    final lhs =
        fitCurveCubic(points.sublist(0, splitPos + 1), startTangent, centerTangent, maxError);
    final rhs = fitCurveCubic(points.sublist(splitPos), centerTangent * -1.0, endTangent,
        maxError);

    return [...lhs, ...rhs];
  }

  static const maxIterations = 8;
  static const maxPointsToFit = 200;

  static int _maxPointsToFit(int numPoints) {
    if (numPoints < maxPointsToFit) {
      return maxPointsToFit;
    }
    final minPoints = maxPointsToFit ~/ 4;
    var result = maxPointsToFit;
    while (result > minPoints && (numPoints % result) < minPoints) {
      result--;
    }
    return result;
  }

  static List<(PointF64, PointF64, PointF64, PointF64)> _fitLine(
      PointF64 p1, PointF64 p2) {
    final direction = p2 - p1;
    final cp1 = p1 + direction * 0.33;
    final cp2 = p1 + direction * 0.66;
    return [(p1.clone(), cp1, cp2, p2.clone())];
  }

  static List<double> _chordsForPoints(List<PointF64> points) {
    final distances = <double>[];
    var totalDistance = 0.0;

    distances.add(totalDistance);
    for (var p = 1; p < points.length; p++) {
      totalDistance += points[p - 1].distanceTo(points[p]);
      distances.add(totalDistance);
    }

    if (totalDistance == 0) {
      return List<double>.filled(points.length, 0.0);
    }
    return distances.map((d) => d / totalDistance).toList();
  }

  static (PointF64, PointF64, PointF64, PointF64) _generateBezier(
      List<PointF64> points,
      List<double> chords,
      PointF64 startTangent,
      PointF64 endTangent) {
    // Precompute the RHS as 'a'.
    final a = <(PointF64, PointF64)>[];
    for (final chord in chords) {
      final inverseChord = 1.0 - chord;
      final b1 = 3.0 * chord * (inverseChord * inverseChord);
      final b2 = 3.0 * chord * chord * inverseChord;
      a.add((startTangent * b1, endTangent * b2));
    }

    // Create the 'C' and 'X' matrices.
    var c00 = 0.0, c01 = 0.0, c11 = 0.0;
    var x0 = 0.0, x1 = 0.0;

    final lastPoint = points[points.length - 1];

    for (var point = 0; point < points.length; point++) {
      c00 += a[point].$1.dot(a[point].$1);
      c01 += a[point].$1.dot(a[point].$2);
      c11 += a[point].$2.dot(a[point].$2);

      final chord = chords[point];
      final inverseChord = 1.0 - chord;
      final b0 = inverseChord * inverseChord * inverseChord;
      final b1 = 3.0 * chord * (inverseChord * inverseChord);
      final b2 = 3.0 * chord * chord * inverseChord;
      final b3 = chord * chord * chord;

      final tmp = points[point] -
          ((points[0] * b0) + (points[0] * b1) + (lastPoint * b2) + (lastPoint * b3));

      x0 += a[point].$1.dot(tmp);
      x1 += a[point].$2.dot(tmp);
    }

    final detC0C1 = c00 * c11 - c01 * c01;
    final detC0X = c00 * x1 - c01 * x0;
    final detXC1 = x0 * c11 - x1 * c01;

    final alphaL = detC0C1.abs() < 1.0e-4 ? 0.0 : detXC1 / detC0C1;
    final alphaR = detC0C1.abs() < 1.0e-4 ? 0.0 : detC0X / detC0C1;

    // Wu/Barsky heuristic when alpha is negligible.
    final segLength = points[0].distanceTo(lastPoint);
    final epsilon = 1.0e-6 * segLength;

    if (alphaL < epsilon || alphaR < epsilon) {
      final dist = segLength / 3.0;
      return (
        points[0].clone(),
        points[0] + (startTangent * dist),
        lastPoint + (endTangent * dist),
        lastPoint.clone(),
      );
    }
    return (
      points[0].clone(),
      points[0] + (startTangent * alphaL),
      lastPoint + (endTangent * alphaR),
      lastPoint.clone(),
    );
  }

  static (double, int) _maxErrorForCurve(
      List<PointF64> points,
      List<double> chords,
      (PointF64, PointF64, PointF64, PointF64) curve) {
    var biggestErrorSquared = 0.0;
    var biggestErrorOffset = 0;

    for (var i = 0; i < points.length; i++) {
      final actual = _pointAtPos(curve, chords[i]);
      final dx = points[i].x - actual.x;
      final dy = points[i].y - actual.y;
      final errorSquared = dx * dx + dy * dy;
      if (errorSquared > biggestErrorSquared) {
        biggestErrorSquared = errorSquared;
        biggestErrorOffset = i;
      }
    }

    return (math.sqrt(biggestErrorSquared), biggestErrorOffset);
  }

  static PointF64 _startTangent(List<PointF64> points) =>
      (points[1] - points[0]).normalized();

  static PointF64 _endTangent(List<PointF64> points) =>
      (points[points.length - 2] - points[points.length - 1]).normalized();

  static PointF64 _tangentBetween(PointF64 p1, PointF64 p2, PointF64 p3) {
    final v1 = p1 - p2;
    final v2 = p2 - p3;
    return ((v1 + v2) * 0.5).normalized();
  }

  static List<double> _reparameterize(List<PointF64> points, List<double> chords,
      (PointF64, PointF64, PointF64, PointF64) curve) {
    final out = <double>[];
    for (var i = 0; i < points.length; i++) {
      out.add(_newtonRaphsonRootFind(curve, points[i], chords[i]));
    }
    return out;
  }

  static PointF64 _pointAtPos(
      (PointF64, PointF64, PointF64, PointF64) curve, double t) {
    final (p0, p1, p2, p3) = curve;
    final u = 1.0 - t;
    final b0 = u * u * u;
    final b1 = 3.0 * t * u * u;
    final b2 = 3.0 * t * t * u;
    final b3 = t * t * t;
    return PointF64(
      b0 * p0.x + b1 * p1.x + b2 * p2.x + b3 * p3.x,
      b0 * p0.y + b1 * p1.y + b2 * p2.y + b3 * p3.y,
    );
  }

  static double _newtonRaphsonRootFind(
      (PointF64, PointF64, PointF64, PointF64) curve, PointF64 point, double estimatedT) {
    final (start, cp1, cp2, end) = curve;

    final qt = _pointAtPos(curve, estimatedT);

    // Control vertices of the derivative.
    final qn1 = (cp1 - start) * 3.0;
    final qn2 = (cp2 - cp1) * 3.0;
    final qn3 = (end - cp2) * 3.0;

    final qnn1 = (qn2 - qn1) * 2.0;
    final qnn2 = (qn3 - qn2) * 2.0;

    // Q'(t) and Q''(t) via de Casteljau on the derivative hulls.
    final qnt = _deCasteljau3(estimatedT, qn1, qn2, qn3);
    final qnnt = _deCasteljau2(estimatedT, qnn1, qnn2);

    final diff = qt - point;
    final numerator = diff.dot(qnt);
    final denominator = qnt.dot(qnt) + diff.dot(qnnt);

    if (denominator == 0.0) {
      return estimatedT;
    }
    return (estimatedT - (numerator / denominator)).clamp(0.0, 1.0);
  }

  static PointF64 _deCasteljau3(double t, PointF64 w1, PointF64 w2, PointF64 w3) {
    final wn1 = w1 * (1.0 - t) + w2 * t;
    final wn2 = w2 * (1.0 - t) + w3 * t;
    return _deCasteljau2(t, wn1, wn2);
  }

  static PointF64 _deCasteljau2(double t, PointF64 w1, PointF64 w2) {
    return w1 * (1.0 - t) + w2 * t;
  }
}
