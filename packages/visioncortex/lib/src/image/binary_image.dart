import 'dart:typed_data';

import '../bound.dart';
import '../color.dart';
import '../point.dart';
import 'color_image.dart';

/// Image with 1 bit per pixel, stored as one byte per pixel (0 or 1) for fast
/// Dart access. `true` = set.
class BinaryImage {
  /// One byte per pixel: nonzero means set.
  Uint8List pixels;

  int width;

  int height;

  BinaryImage(this.pixels, this.width, this.height);

  BinaryImage.newWH(int width, int height)
      : pixels = Uint8List(width * height),
        width = width,
        height = height;

  BinaryImage.empty()
      : pixels = Uint8List(0),
        width = 0,
        height = 0;

  BinaryImage clone() => BinaryImage(Uint8List.fromList(pixels), width, height);

  bool getPixel(int x, int y) => pixels[y * width + x] != 0;

  bool getPixelAt(PointI32 p) => pixels[p.y * width + p.x] != 0;

  /// Out-of-bounds reads return false.
  bool getPixelSafe(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    return pixels[y * width + x] != 0;
  }

  bool getPixelAtSafe(PointI32 p) => getPixelSafe(p.x, p.y);

  void setPixel(int x, int y, bool v) => pixels[y * width + x] = v ? 1 : 0;

  void setPixelAt(PointI32 p, bool v) => setPixel(p.x, p.y, v);

  void setPixelIndex(int i, bool v) => pixels[i] = v ? 1 : 0;

  bool setPixelSafe(int x, int y, bool v) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    setPixel(x, y, v);
    return true;
  }

  BoundingRect boundingRect() {
    final rect = BoundingRect.zero();
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (pixels[row + x] != 0) rect.addXY(x, y);
      }
    }
    return rect;
  }

  int area() {
    var count = 0;
    for (final v in pixels) {
      if (v != 0) count++;
    }
    return count;
  }

  BinaryImage crop() => cropWithRect(boundingRect());

  BinaryImage cropWithRect(BoundingRect rect) {
    final image = BinaryImage.newWH(rect.width, rect.height);
    for (var y = rect.top; y < rect.bottom; y++) {
      for (var x = rect.left; x < rect.right; x++) {
        if (getPixel(x, y)) {
          image.setPixel(x - rect.left, y - rect.top, true);
        }
      }
    }
    return image;
  }

  /// Bitwise complement.
  BinaryImage negative() {
    final out = BinaryImage.newWH(width, height);
    final src = pixels;
    final dst = out.pixels;
    for (var i = 0; i < src.length; i++) {
      dst[i] = src[i] != 0 ? 0 : 1;
    }
    return out;
  }

  /// Parse from an ASCII picture: `*` = set, anything else = clear.
  static BinaryImage fromString(String string) {
    final lines = string.split('\n');
    var width = 0;
    var height = 0;
    for (final line in lines) {
      if (line.isEmpty) continue;
      if (height == 0) width = line.length;
      height++;
    }
    final image = BinaryImage.newWH(width, height);
    var y = 0;
    for (final line in lines) {
      if (line.isEmpty) continue;
      var x = 0;
      for (final c in line.split('')) {
        image.setPixel(x, y, c == '*');
        x++;
      }
      y++;
    }
    return image;
  }

  String toPictureString() {
    final sb = StringBuffer();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        sb.write(getPixel(x, y) ? '*' : '-');
      }
      sb.write('\n');
    }
    return sb.toString();
  }

  ColorImage toColorImage() {
    final image = ColorImage.newWH(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixel(
            x, y, getPixel(x, y) ? Color.black : Color.white);
      }
    }
    return image;
  }

  /// The set of boundary pixels: set pixels with at least one clear
  /// 4-neighbour.
  BinaryImage boundaryImage() =>
      ShapeGeometry.imageBoundaryAndPositionLength(this).$1;
}

/// Shape boundary helpers (ported from visioncortex `Shape`).
class ShapeGeometry {
  /// Returns (boundary image, first boundary pixel, boundary length).
  static (BinaryImage, PointI32?, int) imageBoundaryAndPositionLength(
      BinaryImage image) {
    var length = 0;
    final boundary = BinaryImage.newWH(image.width, image.height);
    PointI32? first;
    final w = image.width;
    final h = image.height;
    final src = image.pixels;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (src[y * w + x] != 0 &&
            (image.getPixelSafe(x - 1, y) == false ||
                image.getPixelSafe(x + 1, y) == false ||
                image.getPixelSafe(x, y - 1) == false ||
                image.getPixelSafe(x, y + 1) == false)) {
          first ??= PointI32(x, y);
          boundary.setPixel(x, y, true);
          length++;
        }
      }
    }
    return (boundary, first, length);
  }

  /// Coordinates of the boundary pixels, in raster order.
  static List<PointI32> imageBoundaryList(BinaryImage image) {
    final boundary = <PointI32>[];
    final w = image.width;
    final h = image.height;
    final src = image.pixels;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (src[y * w + x] != 0 &&
            (image.getPixelSafe(x - 1, y) == false ||
                image.getPixelSafe(x + 1, y) == false ||
                image.getPixelSafe(x, y - 1) == false ||
                image.getPixelSafe(x, y + 1) == false)) {
          boundary.add(PointI32(x, y));
        }
      }
    }
    return boundary;
  }
}
