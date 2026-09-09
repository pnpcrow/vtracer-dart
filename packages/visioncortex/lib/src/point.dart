import 'dart:math' as math;

/// Integer 2D point. Value semantics (like Rust's `Copy` struct).
class PointI32 {
  int x;
  int y;

  PointI32(this.x, this.y);

  PointI32.zero()
      : x = 0,
        y = 0;

  PointI32 clone() => PointI32(x, y);

  PointF64 toPointF64() => PointF64(x.toDouble(), y.toDouble());

  PointI32 operator +(PointI32 o) => PointI32(x + o.x, y + o.y);
  PointI32 operator -(PointI32 o) => PointI32(x - o.x, y - o.y);

  /// Squared euclidean length of the vector (dot with itself).
  int dot(PointI32 o) => x * o.x + y * o.y;

  @override
  bool operator ==(Object other) => other is PointI32 && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}

/// Double 2D point. Value semantics.
class PointF64 {
  double x;
  double y;

  PointF64(this.x, this.y);

  PointF64.zero()
      : x = 0,
        y = 0;

  PointF64 clone() => PointF64(x, y);

  PointI32 toPointI32() => PointI32(x.toInt(), y.toInt());

  PointI32 roundToPointI32() =>
      PointI32(x.roundToDouble().toInt(), y.roundToDouble().toInt());

  PointF64 operator +(PointF64 o) => PointF64(x + o.x, y + o.y);
  PointF64 operator -(PointF64 o) => PointF64(x - o.x, y - o.y);
  PointF64 operator *(double s) => PointF64(x * s, y * s);
  PointF64 operator /(double s) => PointF64(x / s, y / s);
  PointF64 operator -() => PointF64(-x, -y);

  double dot(PointF64 o) => x * o.x + y * o.y;

  double norm() => math.sqrt(x * x + y * y);

  double distanceTo(PointF64 o) {
    final dx = x - o.x;
    final dy = y - o.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Unit vector, or the zero vector when the norm is zero.
  PointF64 normalized() {
    final n = norm();
    if (n == 0) return PointF64.zero();
    return PointF64(x / n, y / n);
  }

  @override
  bool operator ==(Object other) => other is PointF64 && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}
