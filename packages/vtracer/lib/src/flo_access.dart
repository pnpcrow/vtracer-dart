import 'package:visioncortex/visioncortex.dart';

/// Accessor that exposes the Schneider `fitCurveCubic` used by the
/// [SimplifyCurves] pass (thin wrapper to keep the import surface small).
List<(PointF64, PointF64, PointF64, PointF64)> fitCurveCubicAccess(
    List<PointF64> points, PointF64 startTangent, PointF64 endTangent,
    double maxError) {
  return CurveFit.fitCurveCubic(points, startTangent, endTangent, maxError);
}
