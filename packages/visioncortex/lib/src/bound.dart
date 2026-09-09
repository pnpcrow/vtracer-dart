import 'point.dart';

/// The rectangle that bounds an object. Coordinates are exclusive on
/// right/bottom (right = left + width).
class BoundingRect {
  int left;
  int top;
  int right;
  int bottom;

  BoundingRect(this.left, this.top, this.right, this.bottom);

  BoundingRect.zero()
      : left = 0,
        top = 0,
        right = 0,
        bottom = 0;

  BoundingRect clone() => BoundingRect(left, top, right, bottom);

  static BoundingRect newXYWH(int x, int y, int w, int h) =>
      BoundingRect(x, y, x + w, y + h);

  int get width => right - left;
  int get height => bottom - top;

  int get area => width * height;

  bool get isEmpty => width == 0 && height == 0;

  PointI32 center() => PointI32((left + right) >> 1, (top + bottom) >> 1);

  PointI32 topLeft() => PointI32(left, top);
  PointI32 bottomRight() => PointI32(right, bottom);

  /// Expands the rect to include the pixel at `(x, y)` (the unit cell
  /// `[x, x+1) × [y, y+1)`). An empty rect is initialised to exactly that
  /// pixel.
  void addXY(int x, int y) {
    if (isEmpty) {
      left = x;
      right = x + 1;
      top = y;
      bottom = y + 1;
      return;
    }
    if (x < left) {
      left = x;
    } else if (x + 1 > right) {
      right = x + 1;
    }
    if (y < top) {
      top = y;
    } else if (y + 1 > bottom) {
      bottom = y + 1;
    }
  }

  /// Smallest rect enclosing both `this` and `other`; empty rects are ignored.
  void merge(BoundingRect other) {
    if (other.isEmpty) return;
    if (isEmpty) {
      left = other.left;
      top = other.top;
      right = other.right;
      bottom = other.bottom;
      return;
    }
    if (other.left < left) left = other.left;
    if (other.top < top) top = other.top;
    if (other.right > right) right = other.right;
    if (other.bottom > bottom) bottom = other.bottom;
  }

  void translate(PointI32 o) {
    left += o.x;
    top += o.y;
    right += o.x;
    bottom += o.y;
  }

  void clear() {
    left = 0;
    top = 0;
    right = 0;
    bottom = 0;
  }

  bool containsPoint(PointI32 p) =>
      p.x >= left && p.x < right && p.y >= top && p.y < bottom;

  @override
  bool operator ==(Object other) =>
      other is BoundingRect &&
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'BoundingRect(l:$left,t:$top,r:$right,b:$bottom)';
}
