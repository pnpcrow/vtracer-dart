import 'package:visioncortex/visioncortex.dart';

/// The final appearance of a region. Only solid colors are supported today.
class Paint {
  final Color color;

  const Paint.solid(this.color);

  Paint clone() => Paint.solid(color);

  @override
  bool operator ==(Object other) => other is Paint && color == other.color;

  @override
  int get hashCode => color.hashCode;
}

/// A region's pixel coverage: a local binary mask positioned on the canvas.
///
/// Foreground pixels are set. Holes (interior background) may be punched out
/// of the mask already.
class RegionMask {
  BinaryImage image;

  /// Position of the mask's top-left corner in full-canvas coordinates.
  PointI32 offset;

  RegionMask(this.image, this.offset);

  int get width => image.width;
  int get height => image.height;

  /// Number of foreground pixels.
  int area() {
    var count = 0;
    for (final v in image.pixels) {
      if (v != 0) count++;
    }
    return count;
  }

  RegionMask clone() => RegionMask(image.clone(), offset.clone());

  /// Union any number of masks in one pass: the destination is sized from the
  /// combined bounding box and each source is blitted exactly once.
  static RegionMask unionAll(List<RegionMask> masks) {
    if (masks.isEmpty) {
      return RegionMask(BinaryImage.newWH(0, 0), PointI32(0, 0));
    }

    var left = masks.first.offset.x;
    var top = masks.first.offset.y;
    var right = masks.first.offset.x + masks.first.image.width;
    var bottom = masks.first.offset.y + masks.first.image.height;
    for (final m in masks.skip(1)) {
      if (m.offset.x < left) left = m.offset.x;
      if (m.offset.y < top) top = m.offset.y;
      final r = m.offset.x + m.image.width;
      final b = m.offset.y + m.image.height;
      if (r > right) right = r;
      if (b > bottom) bottom = b;
    }

    final width = right - left;
    final height = bottom - top;
    final image = BinaryImage.newWH(width, height);

    for (final src in masks) {
      final dx = src.offset.x - left;
      final dy = src.offset.y - top;
      for (var y = 0; y < src.image.height; y++) {
        for (var x = 0; x < src.image.width; x++) {
          if (src.image.getPixel(x, y)) {
            image.setPixel(x + dx, y + dy, true);
          }
        }
      }
    }

    return RegionMask(image, PointI32(left, top));
  }
}

/// A single paint layer. Layers are painted bottom-to-top.
class Layer {
  Paint paint;
  RegionMask mask;

  Layer(this.paint, this.mask);

  Layer clone() => Layer(paint.clone(), mask.clone());

  /// A copy sharing the mask: color fitting replaces [paint] (and may
  /// rebuild layer lists) but never mutates masks, so masks downstream are
  /// effectively read-only and safe to share with a cached segmentation.
  Layer.sharingMask(Layer other)
      : paint = other.paint,
        mask = other.mask;
}

/// Frontend output: ordered layers over a canvas, in paint order.
class Segmentation {
  int width;
  int height;

  /// Bottom-to-top paint order.
  List<Layer> layers;

  Segmentation(this.width, this.height) : layers = [];

  Segmentation.clone(Segmentation other)
      : width = other.width,
        height = other.height,
        layers = other.layers.map((l) => l.clone()).toList();

  /// A copy whose layers share the original masks. Color fitters assign new
  /// paints but never mutate masks, so re-finishing a cached segmentation
  /// does not need to deep-copy mask data.
  Segmentation.sharingMasks(Segmentation other)
      : width = other.width,
        height = other.height,
        layers = [for (final l in other.layers) Layer.sharingMask(l)];
}

/// A single drawing command in a subpath, in absolute document space.
sealed class PathCmd {
  const PathCmd();
}

class MoveTo extends PathCmd {
  final PointF64 p;
  const MoveTo(this.p);
}

class LineTo extends PathCmd {
  final PointF64 p;
  const LineTo(this.p);
}

class CubicTo extends PathCmd {
  final PointF64 c1;
  final PointF64 c2;
  final PointF64 end;
  const CubicTo(this.c1, this.c2, this.end);
}

class ClosePath extends PathCmd {
  const ClosePath();
}

/// One connected outline: a MoveTo followed by line/cubic segments, usually
/// terminated by [ClosePath].
class SubPath {
  List<PathCmd> commands;

  SubPath() : commands = [];

  SubPath.withCommands(this.commands);

  SubPath clone() {
    final out = SubPath();
    for (final cmd in commands) {
      switch (cmd) {
        case MoveTo(:final p):
          out.commands.add(MoveTo(p.clone()));
        case LineTo(:final p):
          out.commands.add(LineTo(p.clone()));
        case CubicTo(:final c1, :final c2, :final end):
          out.commands.add(CubicTo(c1.clone(), c2.clone(), end.clone()));
        case ClosePath():
          out.commands.add(const ClosePath());
      }
    }
    return out;
  }

  bool get isEmpty => commands.isEmpty;

  /// The starting point of the subpath, if any.
  PointF64? start() {
    if (commands.isNotEmpty && commands.first is MoveTo) {
      return (commands.first as MoveTo).p;
    }
    return null;
  }
}

/// A shape may consist of several subpaths (outer ring plus holes).
class MultiPath {
  List<SubPath> subpaths;

  MultiPath() : subpaths = [];

  MultiPath.withSubpaths(this.subpaths);

  bool get isEmpty => subpaths.every((s) => s.isEmpty);

  void push(SubPath subpath) {
    if (!subpath.isEmpty) {
      subpaths.add(subpath);
    }
  }
}

/// A filled shape in the output document.
class Shape {
  Paint paint;
  MultiPath path;

  Shape(this.paint, this.path);

  Shape clone() => Shape(paint.clone(), MultiPath.withSubpaths(
        path.subpaths.map((s) => s.clone()).toList(),
      ));
}

/// The output document IR.
class VectorDoc {
  int width;
  int height;

  /// Shapes in paint order (first drawn is bottom).
  List<Shape> shapes;

  VectorDoc(this.width, this.height) : shapes = [];

  VectorDoc.clone(VectorDoc other)
      : width = other.width,
        height = other.height,
        shapes = other.shapes.map((s) => s.clone()).toList();
}
