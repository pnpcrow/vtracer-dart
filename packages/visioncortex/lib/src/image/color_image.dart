import 'dart:typed_data';

import '../color.dart';

/// Image with 4 bytes (RGBA) per pixel.
class ColorImage {
  /// Raw RGBA bytes, row-major, 4 per pixel.
  Uint8List pixels;

  int width;

  int height;

  ColorImage(this.pixels, this.width, this.height);

  ColorImage.empty()
      : pixels = Uint8List(0),
        width = 0,
        height = 0;

  ColorImage.newWH(int width, int height)
      : pixels = Uint8List(width * height * 4),
        width = width,
        height = height;

  ColorImage clone() => ColorImage(Uint8List.fromList(pixels), width, height);

  Color getPixel(int x, int y) => getPixelAt(y * width + x);

  Color getPixelAt(int index) {
    final i = index * 4;
    return Color(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]);
  }

  /// Reads the raw RGBA channels of a pixel without allocating a [Color].
  /// Returns `null` when out of bounds.
  Color? getPixelSafe(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    return getPixel(x, y);
  }

  void setPixel(int x, int y, Color color) => setPixelAt(y * width + x, color);

  void setPixelAt(int index, Color color) {
    final i = index * 4;
    pixels[i] = color.r;
    pixels[i + 1] = color.g;
    pixels[i + 2] = color.b;
    pixels[i + 3] = color.a;
  }

  /// Direct byte write, skipping the [Color] allocation on hot paths.
  void setPixelBytes(int x, int y, int r, int g, int b, int a) {
    final i = (y * width + x) * 4;
    pixels[i] = r;
    pixels[i + 1] = g;
    pixels[i + 2] = b;
    pixels[i + 3] = a;
  }
}
