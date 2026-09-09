import '../image/binary_image.dart';
import '../point.dart';
import 'paths.dart';
import 'simplify.dart';
import 'smooth.dart';

/// Series of connecting cubic Bézier curves: `1 + 3·num_curves` points.
class Spline {
  List<PointF64> points;

  Spline(PointF64 start) : points = [start];

  Spline.fromPoints(this.points);

  void add(PointF64 point2, PointF64 point3, PointF64 point4) {
    points.add(point2);
    points.add(point3);
    points.add(point4);
  }

  /// Returns the control-point windows `[c0,c1,c2,c3]` of each curve.
  List<List<PointF64>> getControlPoints() {
    final out = <List<PointF64>>[];
    for (var i = 0; i + 3 < points.length; i += 3) {
      out.add(points.sublist(i, i + 4));
    }
    return out;
  }

  int get length => points.length;

  int get numCurves => points.isEmpty ? 0 : (points.length - 1) ~/ 3;

  bool get isEmpty => points.length <= 3;

  void offsetBy(PointF64 offset) {
    for (final p in points) {
      p.x += offset.x;
      p.y += offset.y;
    }
  }

  /// Spline from an image: polygon-simplify, smooth, then fit.
  static Spline fromImage(
    BinaryImage image,
    bool clockwise,
    double cornerThreshold,
    double outsetRatio,
    double segmentLength,
    int maxIterations,
    double spliceThreshold,
  ) {
    var path = PathI32.imageToPath(image, clockwise, PathSimplifyMode.polygon);
    final smoothed =
        path.smoothed(cornerThreshold, outsetRatio, segmentLength, maxIterations);
    return Spline.fromPathF64(smoothed, spliceThreshold);
  }

  /// Spline by curve-fitting a closed path (last point repeats the first).
  static Spline fromPathF64(PathF64 path, double spliceThreshold) {
    final splicePoints = SubdivideSmooth.findSplicePoints(path, spliceThreshold, true);
    final pts = path.path.sublist(0, path.path.length - 1);
    final len = pts.length;
    if (len <= 1) {
      return Spline(PointF64.zero());
    }
    if (len == 2) {
      final result = Spline(pts[0].clone());
      result.add(pts[1].clone(), pts[1].clone(), pts[1].clone());
      return result;
    }

    var cutPoints = <int>[
      for (var i = 0; i < splicePoints.length; i++)
        if (splicePoints[i]) i
    ];

    if (cutPoints.isEmpty) {
      cutPoints.add(0);
    }
    if (cutPoints.length == 1) {
      cutPoints.add((cutPoints[0] + len ~/ 2) % len);
    }
    final numCutPoints = cutPoints.length;

    var result = Spline(PointF64.zero()); // dummy initialization
    var first = true;
    for (var i = 0; i < numCutPoints; i++) {
      final j = (i + 1) % numCutPoints;

      final current = cutPoints[i];
      final next = cutPoints[j];
      final subpath = _getCircularSubpath(pts, current, next);
      for (final bezierPoints in SubdivideSmooth.fitPointsWithBeziers(subpath, 10.0)) {
        if (first) {
          result = Spline(bezierPoints[0].clone());
          first = false;
        }
        result.add(bezierPoints[1].clone(), bezierPoints[2].clone(), bezierPoints[3].clone());
      }
    }

    return result;
  }

  static List<PointF64> _getCircularSubpath(
      List<PointF64> path, int from, int to) {
    final len = path.length;
    if (from < to) {
      return path.sublist(from, to + 1).map((p) => p.clone()).toList();
    } else if (from > to) {
      return [
        ...path.sublist(from, len).map((p) => p.clone()),
        ...path.sublist(0, to + 1).map((p) => p.clone()),
      ];
    }
    return [];
  }
}
