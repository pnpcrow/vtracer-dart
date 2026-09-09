part of '../colorfit.dart';

/// A color in the OKLab space (Björn Ottosson, 2020): a Euclidean space where
/// distance approximates perceived color difference.
class Oklab {
  final double l;
  final double a;
  final double b;

  const Oklab(this.l, this.a, this.b);

  static double _srgbToLinear(int c8) {
    final c = c8 / 255.0;
    if (c <= 0.04045) {
      return c / 12.92;
    }
    return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static Oklab fromColor(Color color) {
    final r = _srgbToLinear(color.r);
    final g = _srgbToLinear(color.g);
    final b = _srgbToLinear(color.b);

    final l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    final m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    final s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

    final l_ = _cbrt(l);
    final m_ = _cbrt(m);
    final s_ = _cbrt(s);

    return Oklab(
      0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
      1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
      0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    );
  }

  static double _cbrt(double v) {
    if (v < 0) {
      return -math.pow(-v, 1.0 / 3.0).toDouble();
    }
    return math.pow(v, 1.0 / 3.0).toDouble();
  }

  /// Squared Euclidean distance (monotonic with distance; avoids the sqrt).
  double distanceSquared(Oklab other) {
    final dl = l - other.l;
    final da = a - other.a;
    final db = b - other.b;
    return dl * dl + da * da + db * db;
  }
}
