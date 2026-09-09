import '../image/binary_image.dart';
import '../point.dart';
import 'simplify.dart';
import 'smooth.dart';

/// Path of [PointI32].
class PathI32 {
  List<PointI32> path;

  PathI32() : path = [];

  PathI32.fromPoints(this.path);

  static PathI32 empty() => PathI32();

  void add(PointI32 point) => path.add(point);

  PointI32? pop() => path.isEmpty ? null : path.removeLast();

  int get length => path.length;
  bool get isEmpty => length == 0;

  void offsetBy(PointI32 o) {
    for (final p in path) {
      p.x += o.x;
      p.y += o.y;
    }
  }

  PathF64 toPathF64() => PathF64.fromPoints(
      path.map((p) => PointF64(p.x.toDouble(), p.y.toDouble())).toList());

  /// Path simplification: staircase removal then penalty-limited decimation.
  PathI32 simplified(bool clockwise) {
    final p = PathSimplify.removeStaircase(this, clockwise);
    return PathSimplify.limitPenalties(p);
  }

  /// Walk the outline of `image` starting from its first boundary pixel.
  /// `clockwise` picks traversal direction (holes use the opposite).
  static PathI32 imageToPath(BinaryImage image, bool clockwise, PathSimplifyMode mode) {
    switch (mode) {
      case PathSimplifyMode.polygon:
        final path = imageToPathBaseline(image, clockwise);
        return path.simplified(clockwise);
      case PathSimplifyMode.none:
      case PathSimplifyMode.spline:
        return imageToPathBaseline(image, clockwise);
    }
  }

  static PathI32 imageToPathBaseline(BinaryImage image, bool clockwise) {
    final (boundary, start, _length) =
        ShapeGeometry.imageBoundaryAndPositionLength(image);
    var path = <PointI32>[];
    if (start != null) {
      final walker = PathWalker(image, start, clockwise);
      path = walker.walkAll();
    }
    return PathI32.fromPoints(path);
  }

  /// Corner-preserving smoothing via 4-point subdivision.
  PathF64 smoothed(
      double cornerThreshold, double outsetRatio, double segmentLength, int maxIterations) {
    assert(maxIterations > 0);
    var corners = SubdivideSmooth.findCornersI32(this, cornerThreshold, true);
    var path = toPathF64();
    for (var i = 0; i < maxIterations; i++) {
      final result = SubdivideSmooth.subdivideKeepCorners(
          path, corners, outsetRatio, segmentLength, true);
      path = result.$1;
      corners = result.$2;
      if (result.$3) break;
    }
    return path;
  }
}

/// Path of [PointF64].
class PathF64 {
  List<PointF64> path;

  PathF64() : path = [];

  PathF64.fromPoints(this.path);

  void add(PointF64 point) => path.add(point);

  int get length => path.length;
  bool get isEmpty => length == 0;

  PathF64 clone() => PathF64.fromPoints(path.map((p) => p.clone()).toList());
}

/// Walks the boundary of a [BinaryImage] with straight-run optimization,
/// emitting only the turning points.
class PathWalker {
  final BinaryImage image;
  final PointI32 start;
  PointI32 curr;
  PointI32 prev;
  PointI32 prevPrev;
  int length = 0;
  final bool clockwise;
  bool first = true;

  PathWalker(this.image, this.start, this.clockwise)
      : curr = start.clone(),
        prev = start.clone(),
        prevPrev = start.clone();

  static PointI32 dirVec(int dir) {
    switch (dir) {
      case 0:
        return PointI32(0, -1);
      case 1:
        return PointI32(1, -1);
      case 2:
        return PointI32(1, 0);
      case 3:
        return PointI32(1, 1);
      case 4:
        return PointI32(0, 1);
      case 5:
        return PointI32(-1, 1);
      case 6:
        return PointI32(-1, 0);
      case 7:
        return PointI32(-1, -1);
      default:
        throw ArgumentError('bad dir $dir');
    }
  }

  static (PointI32, PointI32) sideVecs(int dir) {
    switch (dir) {
      case 0:
        return (PointI32(-1, -1), PointI32(0, -1));
      case 2:
        return (PointI32(0, 0), PointI32(0, -1));
      case 4:
        return (PointI32(-1, 0), PointI32(0, 0));
      case 6:
        return (PointI32(-1, 0), PointI32(-1, -1));
      default:
        throw ArgumentError('bad dir $dir');
    }
  }

  static PointI32 aheadOf(PointI32 curr, int dir) {
    final vec = dirVec(dir);
    return PointI32(curr.x + vec.x, curr.y + vec.y);
  }

  /// Walk the whole boundary, returning the turning points (the first point is
  /// `start`, the last equals it).
  List<PointI32> walkAll() {
    final out = <PointI32>[];
    while (true) {
      final next = _next();
      if (next == null) break;
      out.add(next);
    }
    return out;
  }

  PointI32? _next() {
    if (first) {
      first = false;
      return start.clone();
    }
    if (curr == start && length > 0) {
      return null;
    }
    var dir = -1;
    while (true) {
      var go = -1;
      final range = clockwise ? const [0, 2, 4, 6] : const [6, 4, 2, 0];
      for (final k in range) {
        final ahead = aheadOf(curr, k);
        if (ahead != prev && ahead != prevPrev) {
          final (a, b) = sideVecs(k);
          if (image.getPixelAtSafe(PointI32(curr.x + a.x, curr.y + a.y)) !=
              image.getPixelAtSafe(PointI32(curr.x + b.x, curr.y + b.y))) {
            go = k;
            break;
          }
        }
      }

      if (go != -1) {
        if (dir != -1 && dir != go) {
          // Direction change: the corner is the current position.
          break;
        }
        dir = go;
        prevPrev = prev;
        prev = curr;
        curr = aheadOf(curr, go);
        length++;
      } else {
        throw StateError('no way to go?');
      }
    }
    if (length > 1000000) {
      throw StateError(
          'STUCK: shape should be broken down first without diagonally connected component');
    }
    return curr.clone();
  }
}
