import 'dart:math' as math;

import 'package:visioncortex/visioncortex.dart';

import 'ir.dart';

/// An optimizer pass rewrites the document in place.
abstract class OptimizerPass {
  void run(VectorDoc doc);
}

/// Round all coordinates to `precision` decimal places.
class QuantizePass implements OptimizerPass {
  final int precision;

  const QuantizePass(this.precision);

  double _round(double v) {
    final factor = math.pow(10.0, precision).toDouble();
    return (v * factor).roundToDouble() / factor;
  }

  PointF64 _roundPt(PointF64 p) => PointF64(_round(p.x), _round(p.y));

  @override
  void run(VectorDoc doc) {
    for (final shape in doc.shapes) {
      for (final sub in shape.path.subpaths) {
        final out = <PathCmd>[];
        for (final cmd in sub.commands) {
          switch (cmd) {
            case MoveTo(:final p):
              out.add(MoveTo(_roundPt(p)));
            case LineTo(:final p):
              out.add(LineTo(_roundPt(p)));
            case CubicTo(:final c1, :final c2, :final end):
              out.add(CubicTo(_roundPt(c1), _roundPt(c2), _roundPt(end)));
            case ClosePath():
              out.add(const ClosePath());
          }
        }
        sub.commands = out;
      }
    }
  }
}

/// Remove zero-length segments and collinear-redundant line vertices.
class CleanupPass implements OptimizerPass {
  const CleanupPass();

  @override
  void run(VectorDoc doc) {
    for (final shape in doc.shapes) {
      final subpaths = <SubPath>[];
      for (final sub in shape.path.subpaths) {
        final simplified = _cleanupSubpath(sub);
        // Keep only subpaths with real geometry.
        var draws = 0;
        for (final c in simplified.commands) {
          if (c is LineTo || c is CubicTo) draws++;
        }
        if (draws > 0) {
          subpaths.add(simplified);
        }
      }
      shape.path = MultiPath.withSubpaths(subpaths);
    }
    doc.shapes.removeWhere((s) => s.path.isEmpty);
  }
}

/// Tolerance for treating two points as coincident.
const double _coincidentEps = 1e-6;

/// Perpendicular-distance tolerance for treating three points as collinear.
const double _collinearEps = 1e-4;

bool _approxEq(PointF64 a, PointF64 b) =>
    (a.x - b.x).abs() < _coincidentEps && (a.y - b.y).abs() < _coincidentEps;

/// Perpendicular distance of `b` from the line through `a` and `c`.
bool _collinear(PointF64 a, PointF64 b, PointF64 c) {
  final cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  final base = math.sqrt(
      (c.x - a.x) * (c.x - a.x) + (c.y - a.y) * (c.y - a.y));
  if (base < _coincidentEps) {
    return true;
  }
  return (cross.abs() / base) < _collinearEps;
}

SubPath _cleanupSubpath(SubPath sub) {
  final out = SubPath();
  // `prev` is the point active before the last emitted command; `last` is
  // the current point after it. Both are needed to test collinearity.
  var prev = PointF64.zero();
  var last = PointF64.zero();

  for (final cmd in sub.commands) {
    switch (cmd) {
      case MoveTo(:final p):
        out.commands.add(MoveTo(p.clone()));
        prev = p.clone();
        last = p.clone();
      case LineTo(:final p):
        if (_approxEq(last, p)) {
          continue; // zero-length
        }
        if (out.commands.isNotEmpty && out.commands.last is LineTo) {
          if (_collinear(prev, last, p)) {
            out.commands[out.commands.length - 1] = LineTo(p.clone());
            last = p.clone(); // anchor `prev` unchanged
            continue;
          }
        }
        out.commands.add(LineTo(p.clone()));
        prev = last.clone();
        last = p.clone();
      case CubicTo(:final c1, :final c2, :final end):
        out.commands.add(CubicTo(c1.clone(), c2.clone(), end.clone()));
        prev = last.clone();
        last = end.clone();
      case ClosePath():
        out.commands.add(const ClosePath());
    }
  }

  return out;
}
