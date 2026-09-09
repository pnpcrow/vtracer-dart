import 'package:visioncortex/visioncortex.dart';

import '../error.dart';

/// Fraction of pixels in the sampled rows that must be transparent before the
/// whole image is keyed.
const double _keyingThreshold = 0.2;

/// Whether the image carries enough transparency to warrant keying.
bool shouldKeyImage(ColorImage img) {
  if (img.width == 0 || img.height == 0) {
    return false;
  }

  final threshold = (img.width * 2 * _keyingThreshold).toInt();
  var transparent = 0;
  final rows = [
    0,
    img.height ~/ 4,
    img.height ~/ 2,
    3 * img.height ~/ 4,
    img.height - 1,
  ];
  for (final y in rows) {
    for (var x = 0; x < img.width; x++) {
      if (img.getPixel(x, y).a == 0) {
        transparent++;
      }
      if (transparent >= threshold) {
        return true;
      }
    }
  }
  return false;
}

bool _colorExists(ColorImage img, Color color) {
  final px = img.pixels;
  for (var i = 0; i < px.length; i += 4) {
    if (px[i] == color.r && px[i + 1] == color.g && px[i + 2] == color.b) {
      return true;
    }
  }
  return false;
}

/// Find a color not present in the image, to be used as the key. Tries the
/// primary/secondary colors first, then a deterministic sweep of the RGB cube.
Color findUnusedColor(ColorImage img) {
  const specials = [
    Color(255, 0, 0),
    Color(0, 255, 0),
    Color(0, 0, 255),
    Color(255, 255, 0),
    Color(0, 255, 255),
    Color(255, 0, 255),
  ];
  for (final c in specials) {
    if (!_colorExists(img, c)) {
      return c;
    }
  }

  // Deterministic sweep: step by a value coprime-ish with 256 to spread out.
  const step = 37;
  for (var r = 0; r < 256; r += step) {
    for (var g = 0; g < 256; g += step) {
      for (var b = 0; b < 256; b += step) {
        final c = Color(r, g, b);
        if (!_colorExists(img, c)) {
          return c;
        }
      }
    }
  }

  throw const NoKeyColorError();
}

/// Recolor every fully-transparent pixel to `key`, in place.
void applyKey(ColorImage img, Color key) {
  final px = img.pixels;
  for (var i = 0; i < px.length; i += 4) {
    if (px[i + 3] == 0) {
      px[i] = key.r;
      px[i + 1] = key.g;
      px[i + 2] = key.b;
      px[i + 3] = key.a;
    }
  }
}
